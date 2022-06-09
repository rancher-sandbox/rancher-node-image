This guide will walk you through how to set up and use the proof of concept OS Management capabilities in Rancher. It was last edited on May 21rd 2022. If you notice any errors, please reach out to me on the rancher-users.slack.com either through a DM to Andrew Gracey or the #cos-toolkit channel (cOS was the old name of Elemental)

Pre-reqs:

-	Rancher Manager 2.6.x
-	Docker or Rancher Desktop
-	Server or VM with TPM 2.x

Notes:
-	Some options are skipped in the interest of clarity
-	For additional simplicity, the image produced here will auto-install 
  - This means that a server booted with the bootstrap image will have it's drive formatted

Known issues at the time of writing:
- [The creation of a Cluster object has to be done before editing the MachineInventory object to add it to the cluster. (The reconciliation trigger is currently only on edit)](https://github.com/rancher-sandbox/rancheros-operator/issues/30)
- [Empty clusters created through the Rancher UI don't work correctly (due to an issue with namespaces)](https://github.com/rancher-sandbox/rancheros-operator/issues/29)
- [Nodes need to be rebooted one additional time to be assigned a hostname.](https://github.com/rancher-sandbox/rancheros-operator/issues/31)


Phases:
-	Operator Install and Setup
-	Bootstrap image creation
-	Create downstream cluster 
-	Install onto system
-	Add machines to cluster
-	Update underlying OS


# Operator Install and Setup

The operator that we add creates a few CRDs:

### rancheros.cattle.io/v1/MachineRegistration
Sets a registration endpoint to allow adding cloud-init details. This will be expanded in the future to give more additional control over the registration process.

### rancheros.cattle.io/v1/MachineInventory
Contains all the machine data provided when the machine is bootstrapped. This includes the TPM hash to allow for validating the node’s identity.
We are looking at adding rancherd “call home” data to the status field here. Still being looked at this.

### rancheros.cattle.io/v1/ManagedOSImage
Tells the system what version of the OS each cluster should be hosted on. If this is not set, the node will stay on the same version.

## Install the helm chart

The chart can be found at: https://github.com/rancher-sandbox/rancheros-operator/releases/download/v0.1.0/rancheros-operator-0.1.0.tgz

To install:
```
helm -n cattle-rancheros-operator-system install --create-namespace rancheros-operator https://github.com/rancher-sandbox/rancheros-operator/releases/download/v0.1.0/rancheros-operator-0.1.0.tgz
```

## Add the MachineRegistration 

We need to add a MachineRegistration object to tell the operator to start listening for registrations. This can be done by applying the following yaml:

Note: You may need to adjust the device to be `/dev/sda/` or whatever device you are installing into.
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

Shortly after applying, if you describe at the object using kubectl, it should have some status fields attached that look like:
```
...
status:
  registrationToken: <token>
  registrationURL: https://<donthackme>/v1-rancheros/registration/<token>
```

This registration URL is how Rancher's system-agent will know where to call home and is needed for the next phase. 

# Build bootstrap ISO image

Next we will build the image that we install the nodes with. For this guide, I’ll stop at the iso creation. We also have instructions for qcow and AMIs available. Also, there are a few ways to build this image but we have built a container that provides all the tools needed. 

Note: We hope to automate this portion of the process to provide an image for each MachineRegistration object via Rancher Manager itself.

You will need to run this on a computer with dockerd or moby installed (Rancher Desktop is my choice, but I’m biased)
This is the basic set of commands to perform the iso build.

Note: Do this in an empty directory so the docker build doesn't take too long.

```
REGISTRATION_URL=`kubectl get machineregistration default -ojsonpath="{.status.registrationURL}"`
curl -s -o reg.yaml $REGISTRATION_URL

curl -sLO https://raw.githubusercontent.com/rancher-sandbox/rancher-node-image/main/Dockerfile
curl -sLO https://raw.githubusercontent.com/rancher-sandbox/rancher-node-image/main/elemental-iso-build

docker build -f ./Dockerfile -t local/elemental-node-image .
bash elemental-iso-build local/elemental-node-image iso ./reg.yaml
```

Now that you have an ISO image, burn it to a USB drive using something like Balena Etcher. (Or `dd` if you are on Linux and already know how to do this)

# Install onto node

Boot the node into the OS loaded on the USB drive. This will automatically install the new OS then reboot. Remove the drive during the reboot. 

Once it boots into the newly installed OS, check that it was assigned a hostname other than locahost. If not, reboot one more time. This is a known issue and will be fixed in an upcoming release.

*Here is where you would ship the device.*

# Create Clusters

To create the target cluster, we need to create an empty cluster provisioning object.

```
apiVersion: provisioning.cattle.io/v1
kind: Cluster
metadata:
  name: elemental-demo-cluster
spec:
  rkeConfig: {}
  kubernetesVersion: v1.21.9+k3s1
```

This cluster will allow nodes to be added to it. As with many of these steps, this will be more streamlined in the UI.

# Add node(s) to cluster

Once the cluster is created (and only after), we can edit the MachineInventory object that was created automatically when the server was bootstrapped.
For a control plane node, the new spec in each of the MachineInventory objects should look like: 

```
spec:
  clusterName: elemental-demo-cluster
  config:
    labels: null
    role: server
```

If you want a node to be just a worker, then use:

```
spec:
  clusterName: elemental-demo-cluster
  config:
    labels: null
    role: agent
```

This will trigger system-agent to install k3s and start the agent/worker. 

# Updating the OS

To tie a cluster to a specific OS version, we can use the ManagedOSImage CRD:

```
kind: ManagedOSImage
apiVersion: rancheros.cattle.io/v1
metadata:
  name: demo-update
spec:
  osImage: <your new image tag>
  clusterTargets:
  - clusterName: elemental-demo-cluster
```

When you create this, your nodes will restart with the new image. I need to do some experimentation on if creating this before the cluster itself triggers the same issue.

