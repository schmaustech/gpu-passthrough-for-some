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

# Set table header format 
divider===============================================
divider=$divider$divider$divider
header="\n %-14s %-14s %-14s %-14s\n"
format=" %-14s %-14s %-14s %-14s\n"
width=80

# Slurp in nic device type ids from lspci
gpuid=`echo $gpuid |sed 's/,/\|/g'`
mapfile -t my_gpus < <(lspci -n|grep -E $gpuid)

# Print out headers 
printf "$header" "GPU Bus ID" "Kernel Driver" "PassThru Avail" "GPU Avail"
printf "%$width.${width}s\n" "$divider"

# Declare empty array to store passthrough details on those that can be unbound also set gpuavail counter to 0
declare -a passthrough=()
gpuavail=0

# Enumerate through the GPUs discovered on host
for (( gpu=0; gpu<${#my_gpus[@]}; gpu++ ))
do
   # Extract GPU bus id and kernel driver if one is in use
   gpubusid=`echo ${my_gpus[$gpu]} | awk '{print $1}'`
   gpudrv=`lspci -kn -s $gpubusid | grep "Kernel driver in use:"| awk -F ": " '{print $2}'`

   # Check if driver is already vfio-pci enabled for given gpu if not flag it as available and add to passthrough array
   if [ "$gpudrv" = "vfio-pci" ]; then
      passthru="Complete"
      gpustate="$gpuavail of $gpunum"
   else
      passthru="Yes"
      # Only add to passthrough if our gpunum argument passed is still less the gpuavail count
      if [[ $gpuavail -lt $gpunum ]]; then
        passthrough+=("$gpubusid")
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
     echo "Unbinding device ${passthrough[$pass]} from kernel driver..."
     echo "Path: /sys/bus/pci/devices/$gpupath/driver/unbind"
     echo -n "${passthrough[$pass]}" > /sys/bus/pci/devices/$gpupath/driver/unbind
     echo "Applying driver override to GPU device ${passthrough[$pass]}..."
     echo "Path: /sys/bus/pci/devices/$gpupath/driver_override"
     echo vfio-pci > /sys/bus/pci/devices/$gpupath/driver_override
     echo "Binding GPU device ${passthrough[$pass]} to vfio-pci..."
     echo "$gpupath" > /sys/bus/pci/drivers/vfio-pci/bind
     echo ""
     echo "Device kernel driver validation..."
     lspci -k -s ${passthrough[$pass]}  
  done
else
  echo "Only ${#passthrough[@]} out of the requested $gpunum of GPUs available for passthrough."
  exit 1 
fi
exit 0
