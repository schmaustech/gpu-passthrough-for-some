## Goal

The goal of this project is to take a worker node with NVIDIA GPUs in an OpenShift cluster and split the GPUs into some being available for container workloads and some being available in passthrough mode for virtual machines.

## Contents
- [Why](#why)
- [Configuration and Validation](#configuration-and-validation)
- [Openshift Virtualization Passthrough](#openshift-virtualization-passthrough)
- [Launch Pod and Virtual Machine Workloads](#launch-pod-and-virtual-machine-workloads)

## Why

A lot of customers ask about mixed workloads on a worker node today when it comes to the use of NVIDIA GPUs.   For example as a customer I want to take a worker node with 8 GPUs on it and have 4 of those GPUs assigned to containers and also have 4 of the GPUs in passthrough mode for virtual machines that run on the same node.  Today however this is not a supported configuration in OpenShift because in order for me to put the GPUs into passthrough mode I have to blacklist the drivers and configure the GPU device ids for vfio-pci.   The method outlined in documentation is an all or nothing scenario in that either all GPUs are available for containers or all GPUs are available as passthrough.

There is however a technical way to provide the mix-mode scenario where in that we do not use the standard method of configuration for vfio-pci passthrough.   Instead we use the concept of unbinding and binding certain devices based on their bus ids within the system.  This allows us to surgically decide which GPU devices are set as passthrough.   This also provides an answer to customers asking for this mixed mode scenario.

## Configuration and Validation

While one can manually configure the vfio-pci passthrough in a large cluster, especially after OpenShift upgrades, we need something that is more automatic to handle the effort.   The answer to this is twofold in that we first need a script that can automate the process of binding some GPUs to vfio-pci and then a mechanism of running that script on OpenShift nodes.   

For the automation script we can use the example code in this repository [here](https://github.com/schmaustech/gpu-passthrough-for-some/blob/main/gpu-passthrough-for-some.sh).   This script will identify all the GPUs of a certain device type and then based on the number of GPUs we defined as passthrough will go through and confim there are the requested number and then unbind and bind them to vfio-pci.

To begin we need to wrap the script into a systemd file that can be applied via a machineconfig.  This starts by us concatenating the scripts and base64 encoding it into a variable.

~~~bash
$ BASE64_SCRIPT=$(cat gpu-passthrough-for-some.sh | base64 -w 0)
$ echo $BASE64_SCRIPT
IyEvYmluL2Jhc2gKIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjCiMgVGhpcyBzY3JpcHQgYWxsb3dzIHVzIHRvIHNldCBzb21lIEdQVXMgdG8gcGFzc3Rocm91Z2ggYmFzZWQgb24gZGV2aWNlIGlkICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIwojIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMKCiMgSG93IHRvIHVzZSB0aGUgc2NyaXB0IGlmIHVzZXIgZG9lcyBub3Qga25vdyBob3cKaG93dG8oKXsKICBlY2hvICJVc2FnZTogZ3B1LXBhc3N0aHJvdWdoLWZvci1zb21lLnNoIC1nIDxncHUgZGV2aWNlIGlkPiAtYyA8bnVtYmVyIG9mIGdwdXM+IgogIGVjaG8gIkV4YW1wbGUgU2luZ2xlIEdQVSBEZXZpY2UgSUQ6IGdwdS1wYXNzdGhyb3VnaC1mb3Itc29tZS5zaCAtZyAxMGRlOjI2YjkgLWMgMSIKICAjZWNobyAiRXhhbXBsZSBNdWx0aSBHUFUgRGV2aWNlIElEOiBncHUtcGFzc3Rocm91Z2gtZm9yLXNvbWUuc2ggLWcgMTBkZToyNmI5fDEwZGU6MjMzNSAtYyA0Igp9CgojIEdldG9wdHMgc2V0dXAgZm9yIHZhcmlhYmxlcyB0byBwYXNzIGZyb20gb3B0aW9ucwp3aGlsZSBnZXRvcHRzIGc6YzpoIG9wdGlvbgpkbwpjYXNlICIke29wdGlvbn0iCmluCmcpIGdwdWlkPSR7T1BUQVJHfTs7CmMpIGdwdW51bT0ke09QVEFSR307OwpoKSBob3d0bzsgZXhpdCAwOzsKXD8pIGhvd3RvOyBleGl0IDE7Owplc2FjCmRvbmUKCiMgTWFrZSBzdXJlIHRoZSB2YXJpYWJsZXMgYXJlIHBvcHVsYXRlZCB3aXRoIHZhbHVlcyBvdGhlcndpc2Ugc2hvdyBob3d0bwppZiAoWyAteiAiJGdwdWlkIiBdIHx8IFsgLXogIiRncHVudW0iIF0pIHRoZW4KICAgaG93dG8KICAgZXhpdCAxCmZpCgojIFNldCB0YWJsZSBoZWFkZXIgZm9ybWF0IApkaXZpZGVyPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0KZGl2aWRlcj0kZGl2aWRlciRkaXZpZGVyJGRpdmlkZXIKaGVhZGVyPSJcbiAlLTE0cyAlLTE0cyAlLTE0cyAlLTE0c1xuIgpmb3JtYXQ9IiAlLTE0cyAlLTE0cyAlLTE0cyAlLTE0c1xuIgp3aWR0aD04MAoKIyBTbHVycCBpbiBuaWMgZGV2aWNlIHR5cGUgaWRzIGZyb20gbHNwY2kKZ3B1aWQ9YGVjaG8gJGdwdWlkIHxzZWQgJ3MvLC9cfC9nJ2AKbWFwZmlsZSAtdCBteV9ncHVzIDwgPChsc3BjaSAtbnxncmVwIC1FICRncHVpZCkKCiMgUHJpbnQgb3V0IGhlYWRlcnMgCnByaW50ZiAiJGhlYWRlciIgIkdQVSBCdXMgSUQiICJLZXJuZWwgRHJpdmVyIiAiUGFzc1RocnUgQXZhaWwiICJHUFUgQXZhaWwiCnByaW50ZiAiJSR3aWR0aC4ke3dpZHRofXNcbiIgIiRkaXZpZGVyIgoKIyBEZWNsYXJlIGVtcHR5IGFycmF5IHRvIHN0b3JlIHBhc3N0aHJvdWdoIGRldGFpbHMgb24gdGhvc2UgdGhhdCBjYW4gYmUgdW5ib3VuZCBhbHNvIHNldCBncHVhdmFpbCBjb3VudGVyIHRvIDAKZGVjbGFyZSAtYSBwYXNzdGhyb3VnaD0oKQpncHVhdmFpbD0wCgojIEVudW1lcmF0ZSB0aHJvdWdoIHRoZSBHUFVzIGRpc2NvdmVyZWQgb24gaG9zdApmb3IgKCggZ3B1PTA7IGdwdTwkeyNteV9ncHVzW0BdfTsgZ3B1KysgKSkKZG8KICAgIyBFeHRyYWN0IEdQVSBidXMgaWQgYW5kIGtlcm5lbCBkcml2ZXIgaWYgb25lIGlzIGluIHVzZQogICBncHVidXNpZD1gZWNobyAke215X2dwdXNbJGdwdV19IHwgYXdrICd7cHJpbnQgJDF9J2AKICAgZ3B1ZHJ2PWBsc3BjaSAta24gLXMgJGdwdWJ1c2lkIHwgZ3JlcCAiS2VybmVsIGRyaXZlciBpbiB1c2U6InwgYXdrIC1GICI6ICIgJ3twcmludCAkMn0nYAoKICAgIyBDaGVjayBpZiBkcml2ZXIgaXMgYWxyZWFkeSB2ZmlvLXBjaSBlbmFibGVkIGZvciBnaXZlbiBncHUgaWYgbm90IGZsYWcgaXQgYXMgYXZhaWxhYmxlIGFuZCBhZGQgdG8gcGFzc3Rocm91Z2ggYXJyYXkKICAgaWYgWyAiJGdwdWRydiIgPSAidmZpby1wY2kiIF07IHRoZW4KICAgICAgcGFzc3RocnU9IkNvbXBsZXRlIgogICAgICBncHVzdGF0ZT0iJGdwdWF2YWlsIG9mICRncHVudW0iCiAgIGVsc2UKICAgICAgcGFzc3RocnU9IlllcyIKICAgICAgIyBPbmx5IGFkZCB0byBwYXNzdGhyb3VnaCBpZiBvdXIgZ3B1bnVtIGFyZ3VtZW50IHBhc3NlZCBpcyBzdGlsbCBsZXNzIHRoZSBncHVhdmFpbCBjb3VudAogICAgICBpZiBbWyAkZ3B1YXZhaWwgLWx0ICRncHVudW0gXV07IHRoZW4KICAgICAgICBwYXNzdGhyb3VnaCs9KCIkZ3B1YnVzaWQiKQogICAgICBmaQogICAgICBsZXQgZ3B1YXZhaWwrKwogICAgICAjIENoZWNrIGlmIGRyaXZlciBvdXRwdXQgd2FzIGVtcHR5IG9uIHN5c3RlbXMgd2hlcmUgbm91dmVhdSB3YXMgYmxhY2tsaXN0ZWQgYW5kIG5vIG52aWRpYSBkcml2ZXJzIHdlcmUgbG9hZGVkIAogICAgICBpZiBbICIkZ3B1ZHJ2IiA9ICIiIF07IHRoZW4KICAgICAgICAgZ3B1ZHJ2PSJOL0EiCiAgICAgIGZpCiAgIGZpCgogICAjIFNldCBncHVzdGF0ZSBmb3Igb3V0cHV0IGJhc2VkIG9uIGNvdW50LiAgSWYgd2UgaGF2ZSBtZXQgdGhlIG51bWJlciByZXF1aXJlZCBzZXQgYXMgbm90IHJlcXVpcmVkIGVsc2UgcHJvdmlkZSBjb3VudHMgCiAgIGlmIFtbICRncHVhdmFpbCAtZ3QgJGdwdW51bSBdXTsgdGhlbgogICAgICBncHVzdGF0ZT0iTm90IFJlcXVpcmVkIgogICBlbHNlCiAgICAgIGdwdXN0YXRlPSIkZ3B1YXZhaWwgb2YgJGdwdW51bSIKICAgZmkKICAgIyBEaXNwbGF5IHRvIGNvbnNvbGUgdGhlIGRldGFpbHMKICAgcHJpbnRmICIkZm9ybWF0IiAkZ3B1YnVzaWQgJGdwdWRydiAkcGFzc3RocnUgIiRncHVzdGF0ZSIKZG9uZQoKIyBMb2FkIHZmaW8tcGNpIGlzIGl0cyBub3QgbG9hZGVkCmlmICEgZ3JlcCAtRSAiXnZmaW9fcGNpICIgL3Byb2MvbW9kdWxlczsgdGhlbgogIGVjaG8gIiAiCiAgZWNobyAtbiAiTG9hZGluZyB2ZmlvLXBjaS4uLiIKICBtb2Rwcm9iZSB2ZmlvLXBjaQogIGVjaG8gIi4uLkRvbmUhIgogIGVjaG8gIiAiCmZpCgojIENoZWNrIGlmIHdlIGhhdmUgZW5vdWdoIEdQVXMgYWxsb2NhdGVkIHRvIGNvbnZlcnQgdG8gdmZpby1wY2kgCmlmIFtbICR7I3Bhc3N0aHJvdWdoW0BdfSAtZXEgJGdwdW51bSBdXTsgdGhlbgogIGVjaG8gIiIKICBlY2hvICIkZ3B1bnVtIEdQVXMgaWRlbnRpZmllZCBmb3IgY29udmVydGluZyB0byBwYXNzdGhyb3VnaC4uLiIKICBlY2hvICIiCgogICMgTG9vcCB0aHJvdWdoIGFycmF5IG9mIGdwdXMgdGhhdCBjYW4gYmUgc2V0IHRvIHZmaW8tcGNpCiAgZm9yICgoIHBhc3M9MDsgcGFzczwkeyNwYXNzdGhyb3VnaFtAXX07IHBhc3MrKyApKQogIGRvCiAgICAgIyBGaXggdXAgZ3B1cGF0aCBvZiBidXMgaWQgLSB0aGUgcGF0aCBpcyAxMiBhbmQgYXJtIHRoYXQgc2hvd3MgYnV0IG9uIHg4NiBzZWVtcyB6ZXJvIHBhZGRpbmcgaXMgbmVlZGVkCiAgICAgaWYgW1sgJHsjcGFzc3Rocm91Z2hbJHBhc3NdfSAtbmUgMTIgXV07IHRoZW4KICAgICAgIGdwdXBhdGg9IjAwMDA6JHtwYXNzdGhyb3VnaFskcGFzc119IgogICAgIGVsc2UKICAgICAgIGdwdXBhdGg9IiR7cGFzc3Rocm91Z2hbJHBhc3NdfSIKICAgICBmaQogICAgIGVjaG8gIiAiCiAgICAgZWNobyAiVW5iaW5kaW5nIGRldmljZSAke3Bhc3N0aHJvdWdoWyRwYXNzXX0gZnJvbSBrZXJuZWwgZHJpdmVyLi4uIgogICAgIGVjaG8gIlBhdGg6IC9zeXMvYnVzL3BjaS9kZXZpY2VzLyRncHVwYXRoL2RyaXZlci91bmJpbmQiCiAgICAgZWNobyAtbiAiJHtwYXNzdGhyb3VnaFskcGFzc119IiA+IC9zeXMvYnVzL3BjaS9kZXZpY2VzLyRncHVwYXRoL2RyaXZlci91bmJpbmQKICAgICBlY2hvICJBcHBseWluZyBkcml2ZXIgb3ZlcnJpZGUgdG8gR1BVIGRldmljZSAke3Bhc3N0aHJvdWdoWyRwYXNzXX0uLi4iCiAgICAgZWNobyAiUGF0aDogL3N5cy9idXMvcGNpL2RldmljZXMvJGdwdXBhdGgvZHJpdmVyX292ZXJyaWRlIgogICAgIGVjaG8gdmZpby1wY2kgPiAvc3lzL2J1cy9wY2kvZGV2aWNlcy8kZ3B1cGF0aC9kcml2ZXJfb3ZlcnJpZGUKICAgICBlY2hvICJCaW5kaW5nIEdQVSBkZXZpY2UgJHtwYXNzdGhyb3VnaFskcGFzc119IHRvIHZmaW8tcGNpLi4uIgogICAgIGVjaG8gIiRncHVwYXRoIiA+IC9zeXMvYnVzL3BjaS9kcml2ZXJzL3ZmaW8tcGNpL2JpbmQKICAgICBlY2hvICIiCiAgICAgZWNobyAiRGV2aWNlIGtlcm5lbCBkcml2ZXIgdmFsaWRhdGlvbi4uLiIKICAgICBsc3BjaSAtayAtcyAke3Bhc3N0aHJvdWdoWyRwYXNzXX0gIAogIGRvbmUKZWxzZQogIGVjaHAgIiIKICBlY2hvICJPbmx5ICR7I3Bhc3N0aHJvdWdoW0BdfSBvdXQgb2YgdGhlIHJlcXVlc3RlZCAkZ3B1bnVtIG9mIEdQVXMgYXZhaWxhYmxlIGZvciBwYXNzdGhyb3VnaC4iCiAgZXhpdCAxIApmaQpleGl0IDAK
~~~

We will also set our GPU device id variable that will get embedded in the machineconfig as the argument for the script.  Here we are specifying a device id for a NVIDIA L40s GPU card.

~~~bash
$ DEVICEID="10de:26b9" # Single device id
~~~

We also have to set the number of GPUs we want to passthrough with vfio-pci.  If we set this number beyond the number of available GPUs the systemd unit will fail on run.  In the environment we are testing on since we have 2 NVIDIA L40s cards per node we will set the count to 1 because we want to have 1 GPU for containers and 1 GPU for virtual machines.

~~~bash
$ GPUCOUNT=1
~~~

Then we have to configure a MachineConfig that will place the base64 encoded script on the system and establish a systemd service to run the script everytime the node boots.

~~~bash
$ cat > gpu-passthrough-for-some-machineconfig.yaml << EOF
kind: MachineConfig
apiVersion: machineconfiguration.openshift.io/v1
metadata:
  name: gpu-passthrough-for-some-systemd-service
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.2.0
    systemd:
      units:
      - name: gpu-passthrough-for-some.service
        enabled: true
        contents: |
          [Unit]
          Description=Identifies and enabled passthough on select network interfaces
          After=NetworkManager-wait-online.service openvswitch.service
          Wants=NetworkManager-wait-online.service openvswitch.service
          [Service]
          RemainAfterExit=yes
          ExecStart=/etc/scripts/gpu-passthrough-for-some.sh -g $DEVICEID -c $GPUCOUNT
          Type=oneshot
          [Install]
          WantedBy=multi-user.target
    storage:
      files:
      - filesystem: root
        path: "/etc/scripts/gpu-passthrough-for-some.sh"
        contents:
          source: data:text/plain;charset=utf-8;base64,$BASE64_SCRIPT
          verification: {}
        mode: 0755
        overwrite: true
EOF
~~~

Now let's create the MachineConfig on the cluster.

~~~bash
$ oc create -f gpu-passthrough-for-some-machineconfig.yaml
machineconfig.machineconfiguration.openshift.io/gpu-passthrough-for-some-systemd-service created
~~~

We need to wait for the node to reboot.  Once `oc get mcp` is responsive and confirms the node is updated we can start to validate.

~~~bash
$ oc get mcp
NAME     CONFIG                                             UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
master   rendered-master-9ba3f805fc1404d3ee1de3912afb4b18   True      False      False      3              3                   3                     0                      21d
worker   rendered-worker-a942d328995407e33865fb34617572cb   True      False      False      2              2                   2                     0                      21d
~~~

Let's check the status of the service by opening a debug pod on the node.  We can see from the below output it identified the GPU and set it to vfio-pci.

~~~bash
sh-5.1# systemctl status gpu-passthrough-for-some.service
● gpu-passthrough-for-some.service - Identifies and enabled passthough on select network interfaces
     Loaded: loaded (/etc/systemd/system/gpu-passthrough-for-some.service; enabled; preset: disabled)
     Active: active (exited) since Tue 2026-02-24 16:20:21 UTC; 22min ago
   Main PID: 4022 (code=exited, status=0/SUCCESS)
        CPU: 62ms

Feb 24 16:20:21 nvd-srv-29.nvidia.eng.rdu2.dc.redhat.com gpu-passthrough-for-some.sh[4022]: /etc/scripts/gpu-passthrough-for-some.sh: line 111: /sys/bus/pci/devices/0000:61:00.0/driver/unbind: No such file or d>
Feb 24 16:20:21 nvd-srv-29.nvidia.eng.rdu2.dc.redhat.com gpu-passthrough-for-some.sh[4022]: Applying driver override to GPU device 61:00.0...
Feb 24 16:20:21 nvd-srv-29.nvidia.eng.rdu2.dc.redhat.com gpu-passthrough-for-some.sh[4022]: Path: /sys/bus/pci/devices/0000:61:00.0/driver_override
Feb 24 16:20:21 nvd-srv-29.nvidia.eng.rdu2.dc.redhat.com gpu-passthrough-for-some.sh[4022]: Binding GPU device 61:00.0 to vfio-pci...
Feb 24 16:20:21 nvd-srv-29.nvidia.eng.rdu2.dc.redhat.com gpu-passthrough-for-some.sh[4022]: Device kernel driver validation...
Feb 24 16:20:21 nvd-srv-29.nvidia.eng.rdu2.dc.redhat.com gpu-passthrough-for-some.sh[4086]: 61:00.0 3D controller: NVIDIA Corporation AD102GL [L40S] (rev a1)
Feb 24 16:20:21 nvd-srv-29.nvidia.eng.rdu2.dc.redhat.com gpu-passthrough-for-some.sh[4086]:         Subsystem: NVIDIA Corporation Device 1851
Feb 24 16:20:21 nvd-srv-29.nvidia.eng.rdu2.dc.redhat.com gpu-passthrough-for-some.sh[4086]:         Kernel driver in use: vfio-pci
Feb 24 16:20:21 nvd-srv-29.nvidia.eng.rdu2.dc.redhat.com gpu-passthrough-for-some.sh[4086]:         Kernel modules: nouveau
Feb 24 16:20:21 nvd-srv-29.nvidia.eng.rdu2.dc.redhat.com systemd[1]: Finished Identifies and enabled passthough on select network interfaces.
~~~

Let's look at the `lspci` output for the GPU devices now in our debug pod.   First let's confirm the GPU devices present.

~~~bash
sh-5.1# lspci -nn|grep NVIDIA
61:00.0 3D controller [0302]: NVIDIA Corporation AD102GL [L40S] [10de:26b9] (rev a1)
e1:00.0 3D controller [0302]: NVIDIA Corporation AD102GL [L40S] [10de:26b9] (rev a1)
~~~

Now let's walk each device and see what kernel module each one is using.  Recall this system has 2 GPUs and we wanted one to be vfio-pci.  The other should be using the nvidia driver because we installed NVIDIA GPU Operator and its corresponding GpuClusterPolicy.

~~~bash
sh-5.1# lspci -k -s 61:00.0
61:00.0 3D controller: NVIDIA Corporation AD102GL [L40S] (rev a1)
	Subsystem: NVIDIA Corporation Device 1851
	Kernel driver in use: vfio-pci
	Kernel modules: nouveau

sh-5.1# lspci -k -s e1:00.0
e1:00.0 3D controller: NVIDIA Corporation AD102GL [L40S] (rev a1)
	Subsystem: NVIDIA Corporation Device 1851
	Kernel driver in use: nvidia
	Kernel modules: nouveau
~~~

One final thing we can do is run the script manually on the node again to also confirm our findings.

~~~bash
# /etc/scripts/passthrough-some-nics.sh -n 15b3:a2dc

 NIC Name     NIC Bus ID       Kernel Driver  OCP BR NIC     PassThru Eligible
====================================================================================================
 enp1s0f0np0    0000:01:00.0   mlx5_core      Yes            No            
 enp1s0f1np1    0000:01:00.1   mlx5_core      Yes            No            
 NA             0002:01:00.0   vfio-pci       No             Complete      
 NA             0002:01:00.1   vfio-pci       No             Complete      
vfio_pci 16384 0 - Live 0xffffd5d69072b000
~~~

## Openshift Virtualization Passthrough

## Launch Pod and Virtual Machine Workloads
