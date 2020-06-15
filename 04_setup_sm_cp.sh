#!/bin/bash
. $(dirname $0)/envrc

# Setup OpenShift Service Mesh Operator and Control Plane

SERVICEMASH_OPERATOR_MANIFEST="https://raw.githubusercontent.com/Maistra/istio-operator/maistra-1.0.0/deploy/servicemesh-operator.yaml"

oc login -u system:admin

oc adm new-project istio-operator --display-name="Service Mesh Operator"
oc project istio-operator
oc apply -n istio-operator -f ${SERVICEMASH_OPERATOR_MANIFEST}

while sleep 3
do
	[  $(oc get po -n istio-operator | grep -c Running ) = $(oc get po -n istio-operator -o name | wc -l) ] && break
done
oc get pod -n istio-operator

# oc logs -n istio-operator $(oc -n istio-operator get pods -l name=istio-operator --output=jsonpath={.items..metadata.name})

oc adm new-project $SM_CP_NS --display-name="Bookretail Service Mesh System"

oc apply -n $SM_CP_NS -f - << EOF
apiVersion: maistra.io/v1
kind: ServiceMeshControlPlane
metadata:
  name: service-mesh-installation
spec:
  threeScale:
    enabled: false
  istio:
    global:
      mtls: false
      disablePolicyChecks: false
      proxy:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 128Mi
    gateways:
      istio-egressgateway:
        autoscaleEnabled: false
      istio-ingressgateway:
        autoscaleEnabled: false
        ior_enabled: false
    mixer:
      policy:
        autoscaleEnabled: false
      telemetry:
        autoscaleEnabled: false
        resources:
          requests:
            cpu: 100m
            memory: 1G
          limits:
            cpu: 500m
            memory: 4G
    pilot:
      autoscaleEnabled: false
      traceSampling: 100.0
    kiali:
      dashboard:
        user: admin
        passphrase: redhat
    tracing:
      enabled: true
EOF

while sleep 3
do
	[ $( oc get po -n $SM_CP_NS -l app | grep -c Running ) = "12" ] && break
done
oc get po -n $SM_CP_NS


# ISTIO_INGRESSGATEWAY_POD=$(oc get pod -l app=istio-ingressgateway -o jsonpath="{.items[0].metadata.name}" -n $SM_CP_NS)
# istioctl -n $SM_CP_NS -i $SM_CP_NS authn tls-check ${ISTIO_INGRESSGATEWAY_POD}

oc get route kiali -n $SM_CP_NS -o jsonpath='{"https://"}{.spec.host}{"\n"}'
oc get route jaeger -n $SM_CP_NS -o jsonpath='{"https://"}{.spec.host}{"\n"}'
