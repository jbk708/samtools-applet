#!/bin/bash
set -e -x -o pipefail

main() {
    # Fail fast: Check Docker service
    if ! sudo systemctl start docker; then
        echo "Failed to start Docker service"
        sudo systemctl status docker
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "Docker daemon is not running"
        exit 1
    fi

    NUM_CORES=$(nproc)
    AVAILABLE_MEM=$(free -g | awk '/^Mem:/{print $2}')
    echo "Available resources: $NUM_CORES cores, ${AVAILABLE_MEM}GB memory"

    i_min_base_quality=${i_min_base_quality:-0}
    i_min_mapping_quality=${i_min_mapping_quality:-0}
    
    mkdir -p "${output_dir:-mosdepth_results}"
    
    echo "Downloading input files..."
    dx-download-all-inputs
    
    for i in "${!i_input_files[@]}"; do
        input_file="${i_input_files[$i]}"
        input_file_name=$(dx describe --name "$input_file")
        echo "Processing $input_file_name..."
        
        input_dir="/data/in/i_input_files/$i"
        input_path="$input_dir/$input_file_name"
        base_name=$(basename "$input_file_name" .bam)
        base_name=$(basename "$base_name" .cram)
        output_prefix=${i_output_prefix:-$base_name}
        output_path="/data/${output_dir:-mosdepth_results}/$output_prefix"
        
        # Copy index file to input directory
        index_file="${i_index_files[$i]}"
        index_file_name=$(dx describe --name "$index_file")
        cp "/data/in/i_index_files/$i/$index_file_name" "$input_dir/"
        
        docker run --cpus=${NUM_CORES} --memory=${AVAILABLE_MEM}G \
            -v /home/dnanexus:/data \
            gfanz/mosdepth \
            -t $NUM_CORES \
            -Q $i_min_base_quality \
            -q $i_min_mapping_quality \
            "$output_path" \
            "$input_path"
        
        echo "Uploading results for $input_file_name..."
        summary_file="${output_dir:-mosdepth_results}/${output_prefix}.mosdepth.summary.txt"
        depth_file="${output_dir:-mosdepth_results}/${output_prefix}.per-base.bed.gz"
        
        summary_id=$(dx upload "$summary_file" --brief)
        depth_id=$(dx upload "$depth_file" --brief)
        
        dx-jobutil-add-output o_coverage_files "$summary_id" --class=file
        dx-jobutil-add-output o_depth_files "$depth_id" --class=file
    done
} 