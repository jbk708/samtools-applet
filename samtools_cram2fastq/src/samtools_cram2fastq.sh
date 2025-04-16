#!/bin/bash
set -e -x -o pipefail

main() {
    # Log the start time
    echo "Starting BAM/CRAM to FASTQ conversion at $(date)"
    
    # Set default flags if not provided
    i_samtools_flags="${i_samtools_flags:--f 4}"
    echo "Using samtools flags: ${i_samtools_flags}"
    
    # Create output array
    o_fastq_files=()
    
    # Process each input file
    for i in "${!i_input_files[@]}"; do
        input_file="${i_input_files[$i]}"
        
        # Download input file
        dx download "$input_file" -o input.file
        
        # Download index file if provided
        if [ -n "${i_index_files[$i]:-}" ]; then
            dx download "${i_index_files[$i]}" -o input.file.bai
        fi
        
        # Get base name for output
        if [ -n "$i_output_prefix" ]; then
            base_name="${i_output_prefix}_$(dx describe --name "$input_file" | sed 's/\.\(bam\|cram\)$//')"
        else
            base_name=$(dx describe --name "$input_file" | sed 's/\.\(bam\|cram\)$//')
        fi
        
        # Check if input is CRAM and reference is provided
        if [[ "$(dx describe --name "$input_file")" == *.cram ]]; then
            if [ -z "$i_reference_genome" ]; then
                dx-jobutil-report-error "Reference genome is required for CRAM files"
                exit 1
            fi
            # Download reference genome for CRAM
            dx download "$i_reference_genome" -o reference.fa
            ref_param="-T reference.fa"
        else
            ref_param=""
        fi
        
        # Extract reads based on flags and convert to FASTQ
        echo "Processing ${base_name}"
        samtools view $ref_param ${i_samtools_flags} -u input.file | \
            samtools fastq -@ $(nproc) - | \
            gzip > "${base_name}.fq.gz"
        
        # Upload result
        output_file=$(dx upload "${base_name}.fq.gz" --brief)
        o_fastq_files+=("$output_file")
        
        # Clean up input files
        rm -f input.file input.file.bai reference.fa
    done
    
    # Return output array
    dx-jobutil-add-output o_fastq_files "${o_fastq_files[@]}" --class=array:file
} 