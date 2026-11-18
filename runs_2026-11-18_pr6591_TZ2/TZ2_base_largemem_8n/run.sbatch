#!/bin/bash
#SBATCH --job-name=p6591_TZ2_base_largemem_8n
#SBATCH --account=hpc-prf-dyncrys
#SBATCH --partition=largemem
#SBATCH --nodes=8
#SBATCH --ntasks-per-node=16
#SBATCH --cpus-per-task=8
#SBATCH --exclusive
#SBATCH --mem=0
#SBATCH --time=08:00:00
#SBATCH --chdir=/scratch/hpc-prf-dyncrys/eprop2d1_Jan/02_Claude/0068_pr6591_anatase_tz2/cases/TZ2_base_largemem_8n
#SBATCH --output=/scratch/hpc-prf-dyncrys/eprop2d1_Jan/02_Claude/0068_pr6591_anatase_tz2/cases/TZ2_base_largemem_8n/slurm-%j.out
set -uo pipefail
module --force purge
module load DefaultModules toolchain/foss/2025b
export LD_LIBRARY_PATH=/scratch/hpc-prf-dyncrys/eprop2d1_Jan/02_Claude/0068_pr6591_anatase_tz2/base/runtime:${LD_LIBRARY_PATH:-}
export CP2K_DATA_DIR=/scratch/hpc-prf-dyncrys/eprop2d1_Jan/02_Claude/0068_pr6591_anatase_tz2/base/source/data
export OMP_NUM_THREADS=8 OMP_PROC_BIND=close OMP_PLACES=cores OMP_STACKSIZE=256M OPENBLAS_NUM_THREADS=1
srun --ntasks=128 --ntasks-per-node=16 --cpus-per-task=8 --cpu-bind=cores --distribution=block:block /scratch/hpc-prf-dyncrys/eprop2d1_Jan/02_Claude/0068_pr6591_anatase_tz2/base/runtime/cp2k.psmp -i input.inp -o output.out > cp2k.stdout 2> cp2k.stderr
echo CP2K_JOB_FINISHED
