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

## Openshift Virtualization Passthrough

## Launch Pod and Virtual Machine Workloads
