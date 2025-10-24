#!/bin/bash
for i in $(seq 120 139)
	do      
		qm status $i  | grep -q "does not exist" || qm destroy $i --purge 
	done
