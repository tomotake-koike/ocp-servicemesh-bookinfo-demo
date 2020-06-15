#!/bin/bash
. $(dirname $0)/envrc

oc login -u system:admin

# Delete Business Application
oc delete  -n $USER_NS all --all
oc delete ns $USER_NS

# Delete ServiceMesh Controle Plane
oc delete -n $SM_CP_NS servicemeshmemberroll default
oc delete -n $SM_CP_NS servicemeshcontrolplane service-mesh-installation
oc delete -n $SM_CP_NS all --all
oc delete ns $SM_CP_NS

# Delete ServiceMesh Operator
SERVICEMASH_OPERATOR_MANIFEST="https://raw.githubusercontent.com/Maistra/istio-operator/maistra-1.0.0/deploy/servicemesh-operator.yaml"
oc delete -n istio-operator -f ${SERVICEMASH_OPERATOR_MANIFEST}
oc delete -n istio-operator all --all
oc get crd -o name | grep -e maistra -e istio | xargs oc delete
oc delete ns istio-operator

