#!/bin/bash
. $(dirname $0)/envrc

# Setup ServiceMeshMemberRoll

oc login -u system:admin

oc apply -n $SM_CP_NS -f - << EOF
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  name: default
spec:
  members:
  - $USER_NS
EOF
oc adm policy add-role-to-user edit $SM_CP_ADMIN -n $SM_CP_NS

# echo -en "\n\n$(oc get project $USER_NS -o template --template='{{.metadata.labels}}')\n\n"

# oc get RoleBinding  -n $USER_NS -l release=istio
# oc get secrets -n $USER_NS -o go-template='{{range .items}}{{if (eq .type "istio.io/key-and-cert") }}{{.metadata.name}}{{"\n"}}{{end}}{{end}}'


# Setup Gateway and VirtualService for Application

oc login -u $SM_CP_ADMIN -p $OCP_PASSWD
oc config set-context --current --namespace=$USER_NS 

oc apply -f - << EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: bookinfo-gateway
spec:
  selector:
    istio: ingressgateway # use istio default controller
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: bookinfo
spec:
  hosts:
  - "*"
  gateways:
  - bookinfo-gateway
  http:
  - match:
    - uri:
        exact: /productpage
    - uri:
        prefix: /static
    - uri:
        exact: /login
    - uri:
        exact: /logout
    - uri:
        prefix: /api/v1/products
    route:
    - destination:
        host: productpage
        port:
          number: 9080
EOF

# Setup DestinationRule for Application

oc apply -f - << EOF
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: productpage
spec:
  host: productpage
  subsets:
  - name: v1
    labels:
      version: v1
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: reviews
spec:
  host: reviews
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  - name: v3
    labels:
      version: v3
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: ratings
spec:
  host: ratings
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  - name: v2-mysql
    labels:
      version: v2-mysql
  - name: v2-mysql-vm
    labels:
      version: v2-mysql-vm
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: details
spec:
  host: details
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
---
EOF


# Add Auto-Injection Annotations

oc config set-context --current --namespace=$USER_NS 

for d in $(oc get deploy -o name)
do
  oc patch $d -p $'spec:\n template:\n  metadata:\n   annotations:\n    sidecar.istio.io/inject: "true"'  
done

while sleep 3
do
	[ $( oc get po -o go-template='{{range .items}}{{$name := .metadata.name}}{{range .spec.containers}}{{if eq .name "istio-proxy"}}{{$name}}{{"\n"}}{{end}}{{end}}{{end}}' | wc -l )  = "6" ] && break
done

while sleep 3
do
	[ $( oc get po | grep -c Running ) = "6" ] && break
done

for p in $( oc get po -o go-template='{{range .items}}{{$name := .metadata.name}}{{range .spec.containers}}{{if eq .name "istio-proxy"}}{{$name}}{{"\n"}}{{end}}{{end}}{{end}}' )
do
	oc get po $p -o go-template='{{.metadata.name}}{{"\t:"}}{{range .spec.containers}}{{" \t"}}{{.name}}{{end}}{{"\n"}}'
done

ISTIO_INGRESSGATEWAY_POD=$(oc get pod -l app=istio-ingressgateway -o jsonpath="{.items[0].metadata.name}" -n $SM_CP_NS)
istioctl -n $SM_CP_NS -i $SM_CP_NS authn tls-check ${ISTIO_INGRESSGATEWAY_POD} | grep \/$USER_NS

