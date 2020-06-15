#!/bin/bash
. $(dirname $0)/envrc

# Setup Liveness/Readyness Probe Command

oc login -u $SM_CP_ADMIN -p $OCP_PASSWD

KUSTOMIZE_DIR=edit-probe
RESOURCE=deploy

mkdir -p $KUSTOMIZE_DIR
oc get $RESOURCE -o yaml > $KUSTOMIZE_DIR/all.yaml
cat << EOF > $KUSTOMIZE_DIR/kustomization.yaml
resources:
- all.yaml
patches:
EOF
for r in $(oc get $RESOURCE -o go-template='{{range .items}}{{.metadata.name}}{{" "}}{{end}}')
do
eval CONTAINER_PORT=$(oc get deploy $r -o go-template='{{range .spec.template.spec.containers}}{{if(.ports)}}{{(index .ports 0).containerPort}}{{end}}{{end}}' )
cat << EOF > $KUSTOMIZE_DIR/$r-patch.yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: $r
spec:
  template:
    spec:
      containers:
      - name: internal-hc
        args:
        - infinity
        command:
        - sleep
        image: registry.redhat.io/openshift-service-mesh/proxyv2-rhel8:1.0.0
        imagePullPolicy: IfNotPresent
        livenessProbe:
          exec:
            command:
            - curl
            - http://127.0.0.1:$CONTAINER_PORT/
          failureThreshold: 3
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 3
        readinessProbe:
          exec:
            command:
            - curl
            - http://127.0.0.1:$CONTAINER_PORT/
          failureThreshold: 3
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 3
EOF
echo "- $r-patch.yaml" >> $KUSTOMIZE_DIR/kustomization.yaml
done
oc apply -k $KUSTOMIZE_DIR

while sleep 3
do
	[ $( oc get po -o go-template='{{range .items}}{{$name := .metadata.name}}{{range .spec.containers}}{{if eq .name "internal-hc"}}{{$name}}{{"\n"}}{{end}}{{end}}{{end}}' | wc -l )  = "6" ] && break
done

while sleep 3
do
	[ $( oc get po | grep -c Running ) = "6" ] && break
done

for p in $( oc get po -o go-template='{{range .items}}{{$name := .metadata.name}}{{range .spec.containers}}{{if eq .name "internal-hc"}}{{$name}}{{"\n"}}{{end}}{{end}}{{end}}' )
do
	oc get po $p -o go-template='{{.metadata.name}}{{"\t:"}}{{range .spec.containers}}{{" \t"}}{{.name}}{{end}}{{"\n"}}'
done



# Create Policies with mTLS STRICT mode

for dr in $(oc get dr -o go-template='{{range .items}}{{.metadata.name}}{{" "}}{{end}}')
do
oc apply -f - << EOF
apiVersion: authentication.istio.io/v1alpha1
kind: Policy
metadata:
  name: $dr
spec:
  peers:
 - mtls:
      mode: STRICT
  targets:
  - name: $dr
EOF
done

# Add ISTIO_MUTUAL mode to DestinationRule

KUSTOMIZE_DIR=add-mtls-dr
RESOURCE=dr

mkdir -p $KUSTOMIZE_DIR
oc get $RESOURCE -o yaml > $KUSTOMIZE_DIR/all.yaml
cat << EOF > $KUSTOMIZE_DIR/kustomization.yaml
resources:
- all.yaml
patches:
EOF
for r in $(oc get $RESOURCE -o go-template='{{range .items}}{{.metadata.name}}{{" "}}{{end}}')
do
cat << EOF > $KUSTOMIZE_DIR/$r-patch.yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: $r
spec:
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF
echo "- $r-patch.yaml" >> $KUSTOMIZE_DIR/kustomization.yaml
done
oc apply -k $KUSTOMIZE_DIR

# Create TLS Secret

SUBDOMAIN_BASE=$(oc get route istio-ingressgateway -n $SM_CP_NS -o go-template='{{.spec.host}}' | cut -d\. -f3-)

mkdir cert
cat << EOF > cert/cert.cfg
[ req ]
req_extensions     = req_ext
distinguished_name = req_distinguished_name
prompt             = no

[req_distinguished_name]
commonName=$USER_NS.apps.$SUBDOMAIN_BASE

[req_ext]
subjectAltName   = @alt_names

[alt_names]
DNS.1  = $USER_NS.apps.$SUBDOMAIN_BASE
DNS.2  = *.$USER_NS.apps.$SUBDOMAIN_BASE
EOF

openssl req -x509 -config cert/cert.cfg -extensions req_ext -nodes -days 730 -newkey rsa:2048 -sha256 -keyout cert/tls.key -out cert/tls.crt
oc get secret istio-ingressgateway-certs -n $SM_CP_NS && oc delete secret istio-ingressgateway-certs
oc create secret tls istio-ingressgateway-certs --cert cert/tls.crt --key cert/tls.key -n $SM_CP_NS
oc delete po -l app=istio-ingressgateway -n $SM_CP_NS

while sleep 3
do
	[ $(oc get po -l app=istio-ingressgateway -n $SM_CP_NS | grep -c Running ) = "1" ] && break
done

# Apply TLS Gateway
oc apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: $GATEWAY_NAME
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      privateKey: /etc/istio/ingressgateway-certs/tls.key
      serverCertificate: /etc/istio/ingressgateway-certs/tls.crt
    hosts:
    - '*.apps.$SUBDOMAIN_BASE'
EOF



# Replace host in VirtualService

oc patch vs bookinfo --type='json' -p "[{\"op\":\"replace\",\"path\":\"/spec/hosts/0\",\"value\":\"$TOP_SERVICE.$USER_NS.apps.$SUBDOMAIN_BASE\"}]"


# Create route for Bookinfo via TLS

oc apply -f - << EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  annotations:
    openshift.io/host.generated: \"true\"
  labels:
    app: $TOP_SERVICE
  name: $TOP_SERVICE
  namespace: $SM_CP_NS
spec:
  host: $TOP_SERVICE.$USER_NS.apps.$SUBDOMAIN_BASE
  port:
    targetPort: https
  tls:
    termination: passthrough
  to:
    kind: Service
    name: istio-ingressgateway
    weight: 100
  wildcardPolicy: None
EOF

oc delete route productpage

ISTIO_INGRESSGATEWAY_POD=$(oc get pod -l app=istio-ingressgateway -o jsonpath="{.items[0].metadata.name}" -n $SM_CP_NS)
istioctl -n $SM_CP_NS -i $SM_CP_NS authn tls-check ${ISTIO_INGRESSGATEWAY_POD} | grep \/bookinfo

echo https://$(oc get route -n $SM_CP_NS $TOP_SERVICE -o go-template='{{.spec.host}}')/$TOP_SERVICE
