#!/bin/bash

# Keep 1 backup per day if older than 7 days
duplicacy prune -keep 1:7

# Keep 1 backup per week if older than 30 days
duplicacy prune -keep 7:30

# Keep 1 backup per 30 days if older than a year
duplicacy prune -keep 30:365

duplicacy prune
