#!/usr/bin/env bash
#
# Copyright (c) 2022 Derek Robson
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Version 0.1 - 2022-06-07 - Basic deployment flow
# Version 0.2 - 2022-06-12 - Remove warnings

# Perform validations
#
set -e

if [ -z "$AZ_LOCATION" ]; then 
    echo "Azure Region location is required to run job"
    exit 1
fi

if [ -z "$AZ_SUBSCRIPTION" ]; then 
    echo "Azure Subscription name required to run job"
    exit 1
fi

if [ -z "$AZ_ARC_CLUSTER" ]; then 
    echo "Azure ARC for Kubernetes Cluster name is required to run job"
    exit 1
fi

if [ -z "$AZ_ARC_CLUSTER_RESOURCE_GROUP" ]; then 
    echo "Azure ARC for Kubernetes Resource Group is required to run job"
    exit 1
fi

if [ -z "$AZ_ARC_DATA_SERVICES_CUSTOM_LOCATION" ]; then 
    echo "Azure ARC Data Services Custom Location is required to run job"
    exit 1
fi

if [ -z "$AZ_ARC_DATA_CONTROLLER" ]; then 
    echo "Azure ARC Data Controller name is required to run job"
    exit 1
fi

if [ -z "$AZ_CUSTOM_LOCATIONS_RP_OBJECT_ID" ]; then 
    echo "Azure Custom Locations Resource Provider Locations Object ID is required to run job"
    exit 1
fi

if [ -z "$KUBE_CLUSTER" ]; then 
    echo "Kubernetes cluster name is required to run job"
    exit 1
fi

if [ -z "$KUBE_ARC_DATA_LOGUI_K8S_SECRET" ]; then 
    echo "Kubernetes secret name for Log UI is required to run job"
    exit 1
fi

if [ -z "$KUBE_ARC_DATA_METRICUI_K8S_SECRET" ]; then 
    echo "Kubernetes secret name for Metic UI is required to run job"
    exit 1
fi

if [ -z "$KUBE_AZ_APP_K8S_SECRET" ]; then 
    echo "Kubernetes secret name for Azure App SP is required to run job"
    exit 1
fi

if [ -z "$LOCAL_RUN" ]; then 
    if [ ! -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]; then 
        echo "Kubernetes service account token does not exist"
        exit 1
    fi

    if [ -z "$KUBE_SECRET_NAMESPACE" ]; then 
        echo "Kubernetes namespace for secrets not provided assuming using namespace of service account"
        export KUBE_SECRET_NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    fi
else 
    echo "Local run skipping service account and secret checks"
fi


if [ -z "$KUBE_ARC_NAMESPACE" ]; then 
    echo "KUBE_ARC_NAMESPACE not provided assuming using azure-arc for Azure ARC for Kubernetes namespace"
    export KUBE_ARC_NAMESPACE='azure-arc'
fi

if [ -z "$KUBE_ARC_DATA_SERVICES_NAMESPACE" ]; then 
    echo "KUBE_ARC_DATA_SERVICES_NAMESPACE not provided assuming using azure-arc-data-services for Azure ARC Data Services namespace"
    export KUBE_ARC_DATA_SERVICES_NAMESPACE='azure-arc-data-services'
fi

if [ -z "$AZ_ARC_DATA_SERVICES_RESOURCE_GROUP" ]; then 
    echo "AZ_ARC_DATA_SERVICES_RESOURCE_GROUP not provided assuming using AZ_ARC_CLUSTER_RESOURCE_GROUP for Data Controller Resource Group"
    export AZ_ARC_DATA_SERVICES_RESOURCE_GROUP=$AZ_ARC_CLUSTER_RESOURCE_GROUP
fi

if [ -z "$AZ_ARC_DATA_SERVICES_EXT_AUTO_UPGRADE" ]; then 
    echo "AZ_ARC_DATA_SERVICES_EXT_AUTO_UPGRADE not provided assuming using false for auto update"
    export AZ_ARC_DATA_SERVICES_EXT_AUTO_UPGRADE='false'
fi

if [ -z "$AZ_ARC_CLUSTER_INFRASTRUCTURE" ]; then 
    echo "AZ_ARC_CLUSTER_INFRASTRUCTURE not provided assuming using auto for infrasture type"
    export AZ_ARC_CLUSTER_INFRASTRUCTURE='auto'
fi

if [ -z "$AZ_ARC_CLUSTER_DISTRIBUTION" ]; then 
    echo "AZ_ARC_CLUSTER_DISTRIBUTION not provided assuming using auto for distribution type"
    export AZ_ARC_CLUSTER_DISTRIBUTION='auto'
fi

if [ -z "$AZ_ARC_DATA_SERVICES_EXT_NAME" ]; then 
    echo "AZ_ARC_DATA_SERVICES_EXT_NAME not provided assuming using azure-arc-data-services for data services extension name"
    export AZ_ARC_DATA_SERVICES_EXT_NAME='azure-arc-data-services'
fi

# Setting up access for Kubernetes using service account
#
if [ -z "$LOCAL_RUN" ]; then 
    kubectl config set-cluster $KUBE_CLUSTER --server=https://kubernetes.default --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    kubectl config set-credentials sa-installer --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) 
    kubectl config set-context sa-context --user=sa-installer --cluster=$KUBE_CLUSTER
    kubectl config use-context sa-context
else 
    echo "Local run skipping service account context"
fi

# Displaying cluster info
#
echo ""
echo "Running on following cluster:"
kubectl cluster-info 
echo ""
echo "Using following config:"
kubectl config view
echo ""

# Check if secrets already exists
#
export KUBE_ARC_DATA_LOGUI_K8S_SECRET_EXISTS=$(kubectl get secrets -n $KUBE_SECRET_NAMESPACE -o=jsonpath="{.metadata.name}")
if [ ! -z "$KUBE_ARC_DATA_LOGUI_K8S_SECRET_EXISTS" ]; then 
    echo "Kubernetes secret $KUBE_ARC_DATA_LOGUI_K8S_SECRET is missing"
    exit 1
else 
    export AZDATA_LOGSUI_USERNAME=$(kubectl get secrets $KUBE_ARC_DATA_LOGUI_K8S_SECRET -n $KUBE_SECRET_NAMESPACE --template={{.data.username}} | base64 -d)
    export AZDATA_LOGSUI_PASSWORD=$(kubectl get secrets $KUBE_ARC_DATA_LOGUI_K8S_SECRET -n $KUBE_SECRET_NAMESPACE --template={{.data.password}} | base64 -d)
fi

export KUBE_ARC_DATA_METRICUI_K8S_SECRET_EXISTS=$(kubectl get secrets -n $KUBE_SECRET_NAMESPACE -o=jsonpath="{.metadata.name}")
if [ ! -z "$KUBE_ARC_DATA_METRICUI_K8S_SECRET_EXISTS" ]; then 
    echo "Kubernetes secret $KUBE_ARC_DATA_METRICUI_K8S_SECRET is missing"
    exit 1
else 
    export AZDATA_METRICSUI_USERNAME=$(kubectl get secrets $KUBE_ARC_DATA_METRICUI_K8S_SECRET -n $KUBE_SECRET_NAMESPACE --template={{.data.username}} | base64 -d)
    export AZDATA_METRICSUI_PASSWORD=$(kubectl get secrets $KUBE_ARC_DATA_METRICUI_K8S_SECRET -n $KUBE_SECRET_NAMESPACE --template={{.data.password}} | base64 -d)
fi

export KUBE_AZ_APP_K8S_SECRET_EXISTS=$(kubectl get secrets -n $KUBE_SECRET_NAMESPACE -o=jsonpath="{.metadata.name}")
if [ ! -z "$KUBE_AZ_APP_K8S_SECRET_EXISTS" ]; then 
    echo "Kubernetes secret $KUBE_AZ_APP_K8S_SECRET is missing"
    exit 1
else 
    export AZ_APP_ID=$(kubectl get secrets $KUBE_AZ_APP_K8S_SECRET -n $KUBE_SECRET_NAMESPACE --template={{.data.appId}} | base64 -d)
    export AZ_APP_CLIENT_SECRET=$(kubectl get secrets $KUBE_AZ_APP_K8S_SECRET -n $KUBE_SECRET_NAMESPACE --template={{.data.secret}} | base64 -d)
    export AZ_TENANT_ID=$(kubectl get secrets $KUBE_AZ_APP_K8S_SECRET -n $KUBE_SECRET_NAMESPACE --template={{.data.tenantId}} | base64 -d)
fi

# Turn off warnings
#
if [ -z "$LOCAL_RUN" ]; then 
    echo "Turning off az cli warnings"
    az config set core.only_show_errors=true --only-show-errors
fi

# Login to Azure
#
echo ""
az login --service-principal -u $AZ_APP_ID -p $AZ_APP_CLIENT_SECRET --tenant $AZ_TENANT_ID --query "[].{\"Available Subscriptions\":name}" --output table
az account set --subscription $AZ_SUBSCRIPTION
export AZ_CURRENT_ACCOUNT=$(az account show --query "name" --output tsv)
echo ""
echo "Current subscription assigned $AZ_CURRENT_ACCOUNT"

# Create Resource Groups
#
export AZ_ARC_CLUSTER_RESOURCE_GROUP_EXISTS=$(az group list | jq -r ".[] | select(.name==\"$AZ_ARC_CLUSTER_RESOURCE_GROUP\") |.name")
if [ ! -z "$AZ_ARC_CLUSTER_RESOURCE_GROUP_EXISTS" ]; then 
    echo "ARC for Kubernetes Resource Group $AZ_ARC_CLUSTER_RESOURCE_GROUP already exists, skipping create"
else 
    echo "Creating ARC for Kubernetes Resource Group $AZ_ARC_CLUSTER_RESOURCE_GROUP"
    az group create --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP --location $AZ_LOCATION 
fi

export AZ_ARC_DATA_SERVICES_RESOURCE_GROUP_EXISTS=$(az group list | jq -r ".[] | select(.name==\"$AZ_ARC_DATA_SERVICES_RESOURCE_GROUP\") |.name")
if [ ! -z "$AZ_ARC_DATA_SERVICES_RESOURCE_GROUP_EXISTS" ]; then 
    echo "ARC Data Services Resource Group $AZ_ARC_DATA_SERVICES_RESOURCE_GROUP already exists, skipping create"
else 
    echo "Creating ARC Data Services Resource Group $AZ_ARC_DATA_SERVICES_RESOURCE_GROUP"
    az group create --resource-group $AZ_ARC_DATA_SERVICES_RESOURCE_GROUP --location $AZ_LOCATION 
fi

# Create ARC for Kubernetes and enable Data Services Extension
#
export AZ_ARC_CLUSTER_EXISTS=$(az resource list --name $AZ_ARC_CLUSTER --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP --query "[?contains(type,'Microsoft.Kubernetes/connectedClusters')].name" --output tsv)
if [ ! -z "$AZ_ARC_CLUSTER_EXISTS" ]; then 
    echo "ARC for Kubernetes resource $AZ_ARC_CLUSTER already exists, skipping create"
    export AZ_ARC_DATA_SERVICES_EXT_EXISTS=$(az k8s-extension list --cluster-name $AZ_ARC_CLUSTER --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP --cluster-type connectedclusters | jq -r ".[] | select(.name==\"$AZ_ARC_DATA_SERVICES_EXT_NAME\") |.name")
    if [ ! -z "$AZ_ARC_DATA_SERVICES_EXT_EXISTS" ]; then 
        echo "ARC for Data Services extension $AZ_ARC_DATA_SERVICES_EXT_NAME already exists, skipping create"
    else
        echo "Creating ARC for Data Services extension $AZ_ARC_DATA_SERVICES_EXT_NAME"
        az k8s-extension create --cluster-name $AZ_ARC_CLUSTER --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP --name $AZ_ARC_DATA_SERVICES_EXT_NAME --cluster-type connectedClusters --extension-type microsoft.arcdataservices --auto-upgrade $AZ_ARC_DATA_SERVICES_EXT_AUTO_UPGRADE --scope cluster --release-namespace $KUBE_ARC_DATA_SERVICES_NAMESPACE --config Microsoft.CustomLocation.ServiceAccount=sa-arc-bootstrapper
            
        echo "Adding access for ARC for Data Services extension $AZ_ARC_DATA_SERVICES_EXT_NAME to Resource Group $AZ_ARC_CLUSTER_RESOURCE_GROUP"
        export AZ_ARC_DATA_SERVICES_EXT_MSI_OBJECT_ID=$(az k8s-extension show --cluster-name $AZ_ARC_CLUSTER --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP --name $AZ_ARC_DATA_SERVICES_EXT_NAME --cluster-type connectedClusters --query "identity.principalId" --output tsv)
        export AZ_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        az role assignment create --assignee-object-id $AZ_ARC_DATA_SERVICES_EXT_MSI_OBJECT_ID --role "Contributor" --scope "/subscriptions/$AZ_SUBSCRIPTION_ID/resourceGroups/$AZ_ARC_CLUSTER_RESOURCE_GROUP"
        az role assignment create --assignee-object-id $AZ_ARC_DATA_SERVICES_EXT_MSI_OBJECT_ID --role "Monitoring Metrics Publisher" --scope "/subscriptions/$AZ_SUBSCRIPTION_ID/resourceGroups/$AZ_ARC_CLUSTER_RESOURCE_GROUP"
    fi   
else 
    echo "Creating ARC for Kubernetes resource $AZ_ARC_CLUSTER"
    az connectedk8s connect --name $AZ_ARC_CLUSTER --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP --location $AZ_LOCATION --custom-locations-oid $AZ_CUSTOM_LOCATIONS_RP_OBJECT_ID --distribution $AZ_ARC_CLUSTER_DISTRIBUTION --infrastructure $AZ_ARC_CLUSTER_INFRASTRUCTURE

    echo "Creating ARC for Data Services extension $AZ_ARC_DATA_SERVICES_EXT_NAME"
    az k8s-extension create --cluster-name $AZ_ARC_CLUSTER --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP --name $AZ_ARC_DATA_SERVICES_EXT_NAME --cluster-type connectedClusters --extension-type microsoft.arcdataservices --auto-upgrade $AZ_ARC_DATA_SERVICES_EXT_AUTO_UPGRADE --scope cluster --release-namespace $KUBE_ARC_DATA_SERVICES_NAMESPACE --config Microsoft.CustomLocation.ServiceAccount=sa-arc-bootstrapper

    echo "Adding access for ARC for Data Services extension $AZ_ARC_DATA_SERVICES_EXT_NAME to Resource Group $AZ_ARC_CLUSTER_RESOURCE_GROUP"
    export AZ_ARC_DATA_SERVICES_EXT_MSI_OBJECT_ID=$(az k8s-extension show --cluster-name $AZ_ARC_CLUSTER --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP --name $AZ_ARC_DATA_SERVICES_EXT_NAME --cluster-type connectedClusters --query "identity.principalId" --output tsv)
    export AZ_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    az role assignment create --assignee-object-id $AZ_ARC_DATA_SERVICES_EXT_MSI_OBJECT_ID --role "Contributor" --scope "/subscriptions/$AZ_SUBSCRIPTION_ID/resourceGroups/$AZ_ARC_CLUSTER_RESOURCE_GROUP"
    az role assignment create --assignee-object-id $AZ_ARC_DATA_SERVICES_EXT_MSI_OBJECT_ID --role "Monitoring Metrics Publisher" --scope "/subscriptions/$AZ_SUBSCRIPTION_ID/resourceGroups/$AZ_ARC_CLUSTER_RESOURCE_GROUP"
fi

# Create Custom Location for Data Controller
#
export AZ_ARC_DATA_SERVICES_CUSTOM_LOCATION_EXISTS=$(az resource list --name $AZ_ARC_DATA_SERVICES_CUSTOM_LOCATION --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP --query "[?contains(type,'Microsoft.ExtendedLocation/customLocations')].name" --output tsv)
if [ ! -z "$AZ_ARC_DATA_SERVICES_CUSTOM_LOCATION_EXISTS" ]; then 
    echo "Custom Location $AZ_ARC_DATA_SERVICES_CUSTOM_LOCATION already exists, skipping create"
else 
    echo "Creating Custom Location $AZ_ARC_DATA_SERVICES_CUSTOM_LOCATION"
    export AZ_ARC_KUBERNETES_ID=$(az connectedk8s show --name $AZ_ARC_CLUSTER --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP  --query id --output tsv)
    export AZ_ARC_DATA_SERVICES_EXT_ID=$(az k8s-extension show --cluster-name $AZ_ARC_CLUSTER --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP  --cluster-type connectedClusters --name $AZ_ARC_DATA_SERVICES_EXT_NAME --query id --output tsv)
    az customlocation create --name $AZ_ARC_DATA_SERVICES_CUSTOM_LOCATION --resource-group $AZ_ARC_CLUSTER_RESOURCE_GROUP --namespace $KUBE_ARC_DATA_SERVICES_NAMESPACE --host-resource-id $AZ_ARC_KUBERNETES_ID --cluster-extension-ids $AZ_ARC_DATA_SERVICES_EXT_ID --location $AZ_LOCATION
fi

# Create Data Controller
#
export AZ_ARC_DATA_CONTROLLER_EXISTS=$(az resource list --name $AZ_ARC_DATA_CONTROLLER --resource-group $AZ_ARC_DATA_SERVICES_RESOURCE_GROUP --query "[?contains(type,'Microsoft.AzureArcData/DataControllers')].name" --output tsv)
if [ ! -z "$AZ_ARC_DATA_CONTROLLER_EXISTS" ]; then 
    echo "Data Controller $AZ_ARC_DATA_CONTROLLER already exists, skipping create"
else 
    echo "Creating Data Controller $AZ_ARC_DATA_CONTROLLER"
    az arcdata dc create --name $AZ_ARC_DATA_CONTROLLER --resource-group $AZ_ARC_DATA_SERVICES_RESOURCE_GROUP --location $AZ_LOCATION --connectivity-mode direct --path ./config --custom-location $AZ_ARC_DATA_SERVICES_CUSTOM_LOCATION
fi

echo ""
echo "Arc Data Services installer script complete"
