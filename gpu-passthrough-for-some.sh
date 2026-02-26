#!/bin/bash
############################################################################################################
# This script allows us to set some GPUs to passthrough based on device id                                 #
############################################################################################################

# How to use the script if user does not know how
howto(){
  echo "Usage: gpu-passthrough-for-some.sh -g <gpu device id> -c <number of gpus>"
  echo "Example Single GPU Device ID: gpu-passthrough-for-some.sh -g 10de:26b9 -c 1"
  #echo "Example Multi GPU Device ID: gpu-passthrough-for-some.sh -g 10de:26b9|10de:2335 -c 4"
}

# Getopts setup for variables to pass from options
while getopts g:c:h option
do
case "${option}"
in
g) gpuid=${OPTARG};;
c) gpunum=${OPTARG};;
h) howto; exit 0;;
\?) howto; exit 1;;
esac
done

# Make sure the variables are populated with values otherwise show howto
if ([ -z "$gpuid" ] || [ -z "$gpunum" ]) then
   howto
   exit 1
fi

# Fix up gpuid input
gpuid=`echo $gpuid |sed 's/,/\|/g'`


# Set table header format 
divider===============================================
divider=$divider$divider$divider
header="\n %-14s %-14s %-14s %-14s %-14s\n"
format=" %-14s %-14s %-14s %-14s %-14s\n"
width=80

# Grab a list of OpenShift nodes that contain GPUs 
mapfile -t my_workers < <(oc get nodes -l feature.node.kubernetes.io/pci-10de.present=true --no-headers=true | awk {'print $1'})

for (( worker=0; worker<${#my_workers[@]}; worker++ ))
do
  declare -a passthrough=()
  gpuavail=0

  # Print out headers
  printf "$header" "GPU Bus ID" "Kernel Driver" "PassThru Avail" "GPU Avail" "Node"
  printf "%$width.${width}s\n" "$divider"

  # Slurp in gpu device type ids from worker with lspci
  mapfile -t my_gpus < <(oc debug -q node/${my_workers[$worker]} -- chroot /host lspci -nn|grep $gpuid|awk {'print $1'})

  # Enumerate through the GPUs discovered on host
  for (( gpu=0; gpu<${#my_gpus[@]}; gpu++ ))
  do
     # Extract GPU bus id and kernel driver if one is in use
     #gpubusid=`echo ${my_gpus[$gpu]} | awk '{print $1}'`
     gpudrv=`oc debug -q node/${my_workers[$worker]} -- chroot /host lspci -kn -s ${my_gpus[$gpu]} | grep "Kernel driver in use:"| awk -F ": " '{print $2}'`

     # Check if driver is already vfio-pci enabled for given gpu if not flag it as available and add to passthrough array
     if [ "$gpudrv" = "vfio-pci" ]; then
        passthru="Complete"
        gpustate="$gpuavail of $gpunum"
     else
        passthru="Yes"
        # Only add to passthrough if our gpunum argument passed is still less the gpuavail count
        if [[ $gpuavail -lt $gpunum ]]; then
          passthrough+=("${my_gpus[$gpu]}")
        fi
        let gpuavail++
        # Check if driver output was empty on systems where nouveau was blacklisted and no nvidia drivers were loaded 
        if [ "$gpudrv" = "" ]; then
           gpudrv="N/A"
        fi
     fi

     # Set gpustate for output based on count.  If we have met the number required set as not required else provide counts 
     if [[ $gpuavail -gt $gpunum ]]; then
        gpustate="Not Required"
     else
        gpustate="$gpuavail of $gpunum"
     fi
     # Display to console the details
     printf "$format" ${my_gpus[$gpu]} $gpudrv $passthru "$gpustate" "${my_workers[$worker]}"
  done

  # Load vfio-pci is its not loaded
  if ! oc debug -q node/${my_workers[$worker]} -- chroot /host grep -E "^vfio_pci " /proc/modules > /dev/null 2>&1; then
    echo " "
    echo -n "Loading vfio-pci..."
    oc debug -q node/${my_workers[$worker]} -- chroot /host modprobe vfio-pci
    echo "...Done!"
    echo " "
  else 
    echo " "
    echo "Kernel module vfio-pci already loaded!"
    echo " "
  fi

  # This will kill off processes that are holding GPU device 
  oc debug -q node/${my_workers[$worker]} -- chroot /host /bin/bash -c "kill -9 \$(lsof +c 0 /run/nvidia/driver/dev/nvidia*|grep -E \"nvidia-persis|nvidia-device|nv-hostengine\"| sort |awk {'print \$2'}| uniq)"

  # Check if we have enough GPUs allocated to convert to vfio-pci 
  if [[ ${#passthrough[@]} -eq $gpunum ]]; then
    echo ""
    echo "$gpunum GPUs identified for converting to passthrough..."
    echo ""

    # Loop through array of gpus that can be set to vfio-pci
    for (( pass=0; pass<${#passthrough[@]}; pass++ ))
    do
       # Fix up gpupath of bus id - the path is 12 and arm that shows but on x86 seems zero padding is needed
       if [[ ${#passthrough[$pass]} -ne 12 ]]; then
         gpupath="0000:${passthrough[$pass]}"
       else
         gpupath="${passthrough[$pass]}"
       fi
       echo " "
       echo "Working on node ${my_workers[$worker]} GPUs..."
       echo " "
       echo "Unbinding device ${passthrough[$pass]} from kernel driver..."
       echo "Path: /sys/bus/pci/devices/$gpupath/driver/unbind"
       command="echo -n $gpupath > /sys/bus/pci/devices/$gpupath/driver/unbind"
       oc debug -q node/${my_workers[$worker]} -- chroot /host /bin/bash -c "$command"
       echo "Applying driver override to GPU device ${passthrough[$pass]}..."
       echo "Path: /sys/bus/pci/devices/$gpupath/driver_override"
       command="echo -n vfio-pci > /sys/bus/pci/devices/$gpupath/driver_override"
       oc debug -q node/${my_workers[$worker]} -- chroot /host /bin/bash -c "$command"
       echo "Binding GPU device ${passthrough[$pass]} to vfio-pci..."
       command="echo -n $gpupath > /sys/bus/pci/drivers/vfio-pci/bind"
       oc debug -q node/${my_workers[$worker]} -- chroot /host /bin/bash -c "$command"
       echo " "
       echo "Device kernel driver validation..."
       oc debug -q node/${my_workers[$worker]} -- chroot /host lspci -k -s ${passthrough[$pass]}  
       echo " "
    done
  else
    echo " "
    echo "Only ${#passthrough[@]} out of the requested $gpunum of GPUs available for passthrough."
    exit 1 
  fi

  # The nvidia processes we killed will all restart with the exception of nvidia-persistenced
  # We need to go into the daemonset pod and restart it
  container=`oc get pods -n nvidia-gpu-operator -o wide --field-selector spec.nodeName=nvd-srv-29.nvidia.eng.rdu2.dc.redhat.com -l app.kubernetes.io/component=nvidia-driver --no-headers| awk {'print $1'}`
  oc rsh -n nvidia-gpu-operator $container rm -r -f /var/run/nvidia-persistenced/*
  oc rsh -n nvidia-gpu-operator $container nvidia-persistenced --persistence-mode
done

exit 0
