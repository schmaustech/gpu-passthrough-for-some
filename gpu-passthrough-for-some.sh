#!/bin/bash
############################################################################################################
# This script allows us to set some GPUs to passthrough based on device id                                 #
############################################################################################################

# How to use the script if user does not know how
howto(){
  echo "Usage: gpu-passthrough-for-some.sh -g <gpu device id> -c <number of gpus>"
  echo "Example Single GPU Device ID: gpu-passthrough-for-some.sh -g 10de:26b9 -c 1"
  echo "Example Multi GPU Device ID: gpu-passthrough-for-some.sh -g 10de:26b9|10de:2335 -c 4"
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

# Set table header format 
divider===============================================
divider=$divider$divider$divider
header="\n %-12s %-16s %-14s %-14s %-14s\n"
format=" %-14s %-14s %-14s %-14s %-14s\n"
width=100

# Slurp in nic device type ids from lspci
gpuid=`echo $gpuid |sed 's/,/\|/g'`
mapfile -t my_gpus < <(lspci -n|grep -E $gpuid)

# Print out headers 
printf "$header" "GPU Bus ID" "Kernel Driver" "PassThru Eligible" "GPU Available"
printf "%$width.${width}s\n" "$divider"

# Declare empty array to store nic details on those that can be unbound
declare -a passthrough=()
gpuavail=0

for (( gpu=0; gpu<${#my_gpus[@]}; gpu++ ))
do
   gpubusid=`echo ${my_gpus[$gpu]} | awk '{print $1}'`
   gpudrv=`lspci -kn -s $gpubusid | grep "Kernel driver in use:"| awk -F ": " '{print $2}'`

   # Check if driver is already vfio-pci enabled for given gpu if not flag it
   if [ "$gpudrv" = "vfio-pci" ]; then
      passthru="Complete"
   else
      passthru="Yes"
      #passthrough+=("$gpubusid")
      let gpuavail++
      if [ "$gpudrv" = "" ]; then
         gpudrv="N/A"
      fi
   fi

   if [[ $gpuavail -gt $gpunum ]]; then
      gpustate="Not Required"
   else
      gpustate="$gpuavail of $gpunum"
      passthrough+=("$gpubusid")
   fi
   # Display to console the details
   printf "$format" $gpubusid $gpudrv $passthru "$gpustate"
done

# Load vfio-pci is its not loaded
if ! grep -E "^vfio_pci " /proc/modules; then
  echo " "
  echo -n "Loading vfio-pci..."
  modprobe vfio-pci
  echo "...Done!"
  echo " "
fi

if [[ ${#passthrough[@]} -eq $gpunum ]]; then
  echo ""
  echo "$gpunum GPUs identified for converting to passthrough..."
  echo ""

  # Loop through array of gpus that can be set to vfio-pci
  for (( pass=0; pass<${#passthrough[@]}; pass++ ))
  do
     if [[ ${passthrough[pass]} -ne 12 ]]; then
       gpupath="0000:${passthrough[pass]}"
     fi
     echo " "
     echo "Unbinding device ${passthrough[$pass]} from kernel driver..."
     echo "Path: /sys/bus/pci/devices/$gpupath/driver/unbind"
     #echo -n "${passthrough[$pass]}" > /sys/bus/pci/devices/$gpupath/driver/unbind
     echo "Applying driver override to GPU device ${passthrough[$pass]}..."
     echo "Path: /sys/bus/pci/devices/$gpupath/driver_override"
     #echo vfio-pci > /sys/bus/pci/devices/$gpupath/driver_override
     echo "Binding GPU device ${passthrough[$pass]} to vfio-pci..."
     #echo "$gpupath" > /sys/bus/pci/drivers/vfio-pci/bind
     echo "Device kernel driver validation..."
     lspci -k -s ${passthrough[$pass]}
     #echo "0000:61:00.0" > /sys/bus/pci/devices/0000\:61\:00.0/driver/unbind
     #echo vfio-pci > /sys/bus/pci/devices/0000\:61\:00.0/driver_override
     #echo "0000:61:00.0" > /sys/bus/pci/drivers/vfio-pci/bind
     
  done
else
  echo "Only ${#passthrough[@]} out of the requested $gpunum of GPUs available for passthrough."
  exit 1 
fi
exit 0
