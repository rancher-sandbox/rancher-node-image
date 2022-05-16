This guide will walk you through how to set up and use the proof of concept Rancher OS Management capabilities. It was written on March 23rd 2022. If you notice any errors, please reach out to me on the rancher-users.slack.com either through a DM to Andrew Gracey or the #cos-toolkit channel (cOS was the old name of Elemental)

Pre-reqs:

-	Rancher Manager 2.6.x
-	Docker or Rancher Desktop
-	Server or VM with TPM 2.x

Notes:
-	Some steps or options are skipped in the interest of clarity
-	For additional simplicity, the image produces will auto-install

Known issues at the time of writing:
-	The creation of a Cluster object has to be done before editing the MachineInventory object to add it to the cluster. (The reconciliation trigger is currently only on edit)
- Empty clusters created through the Rancher UI don't work correctly


Phases:
-	Operator Install and Setup
-	Bootstrap image creation
-	Create downstream cluster 
-	Install onto system
-	Add machines to cluster
-	Update underlying OS


TODO: roll in new changes

# Operator Install and Setup

The operator that we add creates a few CRDs:

### rancheros.cattle.io/v1/MachineRegistration
Sets a registration endpoint to allow adding cloud-init details. This will be expanded in the future to give more additional control over the registration process.

### rancheros.cattle.io/v1/MachineInventory
Contains all the machine data provided when the machine is bootstrapped. This includes the TPM hash to allow for validating the node’s identity.
We are looking at adding rancherd “call home” data to the status field here. Still being looked at this.

### rancheros.cattle.io/v1/ManagedOSImage
Tells the system what version of the OS each cluster should be hosted on. If this is not set, the node will stay on the same version 

TODO: Add OS upgrade stream 

## Install the helm chart

The chart can be found at: https://github.com/rancher-sandbox/os2/releases/download/v0.1.0-alpha21/rancheros-operator-0.1.0-alpha21-amd64.tgz 

To install:
```
helm -n cattle-rancheros-operator-system install --create-namespace rancheros-operator https://github.com/rancher-sandbox/os2/releases/download/v0.1.0-alpha21/rancheros-operator-0.1.0-alpha21-amd64.tgz
```

## Add the MachineRegistration 

TODO: Validate fix

We need to add a MachineRegistration object to tell the operator to start listening for registrations. This can be done by applying the yaml:
```
apiVersion: rancheros.cattle.io/v1
kind: MachineRegistration
metadata:
  name: default
  namespace: default
spec:
  cloudConfig:
    rancheros:
      install:
        device: /dev/nvme0n1
    users:
    - name: root
      passwd: root
```

Shortly after applying, if you look at the object, it should have some status fields attached that look like:
```
...
status:
  registrationToken: <token>
  registrationURL: https://<donthackme>/v1-rancheros/registration/<token>
```

This registration URL is how rancherd will know where to call home and is needed for the next phase. 

# Build bootstrap ISO image

Next we will build the image that we install the nodes with. For this guide, I’ll stop at the iso creation. We also have instructions for qcow and AMIs available. Also, there are a few ways to build this image but we have built a container that provides all the tools needed. 

Note: We hope to automate this portion of the process to provide an image for each MachineRegistration object via Rancher Manager itself.

You will need to run this on a computer with dockerd or moby installed (Rancher Desktop is my choice, but I’m biased)
This is the basic set of commands to perform the iso build.


TODO: Fix with latest features

```
REGISTRATION_URL=`kubectl get machineregistration default -ojsonpath="{.status.registrationURL}"`

curl -s -o reg.yaml $REGISTRATION_URL

# fix these quotes when you copy
echo “        ejectCD: true” >> reg.yaml
echo “        powerOff: true” >> reg.yaml
echo “        containerImage: quay.io/costoolkit/os2:v0.1.0-amd64” >> reg.yaml

cat reg.yaml ## Verify that the indentation is correct

curl -sLO https://raw.githubusercontent.com/rancher-sandbox/rancher-node-image/main/elemental-iso-build

bash elemental-iso-build quay.io/costoolkit/os2:v0.1.0-amd64 iso ./reg.yaml
```

Now that you have an ISO image, burn it to a USB drive using something like Balena Etcher. (Or `dd` if you are on Linux and already know how to do this)

# Install onto node

TODO: Validate new build is automatic

Boot the node into the OS loaded on the USB drive. Log in with root/ros as prompted then run:
```
ros-installer -automatic
```

Once this completes and powers off, remove the drive. 

Boot and verify that a hostname got set.

*Here is where you would ship the device.*

# Create Clusters

To create the target cluster, we need to create a cluster provisioning object. Make sure to pick IP ranges that don’t conflict and a Kubernetes version that can be managed. 

TODO: validate without rke config section

```
apiVersion: provisioning.cattle.io/v1
kind: Cluster
metadata:
  name: elemental-test-cluster
spec:
  kubernetesVersion: v1.21.9+k3s1
```

This cluster will allow nodes to be added to it. As with many of these steps, this will be much more streamlined in the UI.

# Add node(s) to cluster

Once the cluster is created (and only after), we can edit the MachineInventory object that was created automatically when the server was bootstrapped.
For a control plane node, the new spec in each of the MachineInventory objects should look like: 

```
spec:
  clusterName: elemental-test-cluster
  config:
    labels: null
    role: server
```

If you want a node to be just a worker, then use:

```
spec:
  clusterName: elemental-test-cluster
  config:
    labels: null
    role: agent
```

This should trigger Rancherd to install k3s and start the agent/worker. 

# Updating the OS


TODO: Add new channel functionality

Note: I will try to get a different OS image to update to.
To tie a cluster to a specific OS version, we can use the ManagedOSImage CRD:

```
kind: ManagedOSImage
apiVersion: rancheros.cattle.io/v1
metadata:
  name: test-update
spec:
  osImage: quay.io/costoolkit/os2:v0.1.0-alpha21-amd64
  clusterTargets:
  - clusterName: elemental-test-cluster
```

When you create this, your nodes will restart with the new image. I need to do some experimentation on if creating this before the cluster itself triggers the same issue.