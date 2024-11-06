#!/bin/bash
#SBATCH --job-name=cuda_mps_job       # Job name
#SBATCH --output=cuda_mps_output.%j    # Output file
#SBATCH --error=cuda_mps_error.%j      # Error file
#SBATCH --ntasks=1                     # Number of tasks (processes)
#SBATCH --cpus-per-task=6              # Number of CPU cores per task (adjust as needed)
#SBATCH --gres=mps:25                   # Request MPS shares
#SBATCH --time=01:00:00                # Time limit (adjust as needed)
#SBATCH --partition=hpc                # Specify the GPU partition (adjust as needed)

# Define directories for MPS control pipes and logs
export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps-$SLURM_JOB_ID
export CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log-$SLURM_JOB_ID

# Create the necessary directories
mkdir -p $CUDA_MPS_PIPE_DIRECTORY
mkdir -p $CUDA_MPS_LOG_DIRECTORY

# Start the MPS control daemon if it isn't already running
if ! pgrep -x "nvidia-cuda-mps-control" > /dev/null; then
    echo "Starting MPS control daemon..."
        nvidia-cuda-mps-control -d
fi

# Set the MPS thread utilization limit (optional)
export CUDA_MPS_ACTIVE_THREAD_PERCENTAGE=25

# Load your Python environment
source /shared/home/vinil/anaconda3/etc/profile.d/conda.sh
conda activate training_env

# Run your CUDA applications
echo "Running CUDA applications..."
python distributed_training.py

# Clean up MPS directories (optional)
echo "Stopping MPS control daemon..."
echo quit | nvidia-cuda-mps-control

# Clean up MPS directories
rm -rf $CUDA_MPS_PIPE_DIRECTORY
rm -rf $CUDA_MPS_LOG_DIRECTORY