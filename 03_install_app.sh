#!/bin/bash
. $(dirname $0)/envrc

# Install Business Application

oc login -u $SM_CP_ADMIN -p $OCP_PASSWD

oc new-project $USER_NS
oc config set-context --current --namespace=$USER_NS
oc apply -f https://raw.githubusercontent.com/istio/istio/1.4.0/samples/bookinfo/platform/kube/bookinfo.yaml
oc expose service productpage
oc create -f - << EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: allow-from-all-namespaces
spec:
  podSelector: {}
  ingress:
    - from:
        - namespaceSelector: {}
  policyTypes:
    - Ingress
EOF

echo -e "http://$(oc get route productpage --template '{{ .spec.host }}')"
