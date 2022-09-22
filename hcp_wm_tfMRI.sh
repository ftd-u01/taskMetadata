#!/bin/bash
# Runs a simple block-design analysis on HCP working memory (WM) tfMRI data.
# Discards first 8 s (10 volumes @ TR = 800 ms) from BOLD timeseries.
# Simple confound regression using csf, white_matter, tcompcor, and dvars predictors
# estimated by fmriprep.
# Also creates lineplots comparing average observed and model-fitted timeseries for
# 8 regions of interest.
# Requires AFNI and R with ggplot2 library.
# Jeff Phillips, 08/25/2022

module load afni_openmp/20.1
module load R/4.1

infile=$1 # BOLD timeseries file, prior to removing first 10 volumes
ccf_dir=$2 # directory with FSL-format event files for WM task conditions
outdir=/project/ftdc_analysis/hcp_tfMRI

# Output stem
stem=`basename ${infile/_space-T1w_desc-preproc_bold.nii.gz}`
# Working directory
wd=`dirname ${infile}`
cd ${outdir}

# Confound file names--reduce the 400+ fmriprep confounds to just 4.
confound_file=${wd}/${stem}_desc-confounds_timeseries.tsv
ortvec=${outdir}/${stem}_desc-ortvec4_timeseries.tsv

# Names of EVs in ccf_dir.
fsl1="0bk_faces.txt"
fsl2="0bk_places.txt"
fsl3="2bk_faces.txt"
fsl4="2bk_places.txt"

# Condition labels, needed for naming the AFNI-format stim_times files.
c1='faces_0bk'
c2='places_0bk'
c3='faces_2bk'
c4='places_2bk'

# Drop first 10 volumes from BOLD timeseries.
echo "Processing ${infile}..."
boldts=${outdir}/`basename ${infile/preproc/drop10}`
3dcalc -a ${infile}'[10..364]' -overwrite -expr 'a' -prefix ${boldts}
3drefit -view orig -space ORIG ${boldts}

# Find indices of csf, white_matter, tcompcor, and dvars predictors in confounds file.
echo "Creating ortvec file..."
confounds=(`head -1 ${confound_file}`)
for i in ${!confounds[@]}; do
    if [[ "${confounds[i]}" == "csf" ]]; then csf_index=${i}; fi
    if [[ "${confounds[i]}" == "white_matter" ]]; then white_matter_index=${i}; fi
    if [[ "${confounds[i]}" == "tcompcor" ]]; then tcompcor_index=${i}; fi
    if [[ "${confounds[i]}" == "dvars" ]]; then dvars_index=${i}; fi
done

# Extract those confounds into ortvec file in the analysis directory.
tail -n +2 ${confound_file} | while read this_line; do
    vals=(`echo ${this_line}`)
    echo "${vals[$csf_index]} ${vals[$white_matter_index]} ${vals[$tcompcor_index]} ${vals[$dvars_index]}"
done > ${ortvec}_tmp
echo "csf white_matter tcompcor dvars" > ${ortvec}
tail -n +11 ${ortvec}_tmp >> ${ortvec}

# Get stimulus onset times for 4 target conditions from FSL-format event files,
# create AFNI-format stim_times files.
echo "Creating stim_times files..."
c1_times=`cat ${ccf_dir}/${fsl1} | while read a b c; do echo $a; done`
echo ${c1_times} > ${outdir}/${stem}_${c1}_times.txt
c2_times=`cat ${ccf_dir}/${fsl2} | while read a b c; do echo $a; done`
echo ${c2_times} > ${outdir}/${stem}_${c2}_times.txt
c3_times=`cat ${ccf_dir}/${fsl3} | while read a b c; do echo $a; done`
echo ${c3_times} > ${outdir}/${stem}_${c3}_times.txt
c4_times=`cat ${ccf_dir}/${fsl4} | while read a b c; do echo $a; done`
echo ${c4_times} > ${outdir}/${stem}_${c4}_times.txt

# Run 3dDeconvolve
echo "Running regression..."
scriptdir=`dirname $0`
3dresample -rmode NN -overwrite -master ${boldts} -inset ${wd}/../anat/*rec-norm_label-GM_probseg.nii.gz -prefix ${outdir}/${stem}_rec-norm_label-GM_mask.nii.gz

${scriptdir}/hcp_wm_3ddecon_block.sh ${boldts}

# Get timeseries for regions of interest.
echo "Extracting timeseries for select ROIs..."
seg=${wd}/${stem}_space-T1w_desc-aparcaseg_dseg.nii.gz
l_cb=8 # Left cerebellar cortex
l_ip=1008 # Left inferior parietal
l_rmf=1027 # Left rostral middle frontal gyrus
l_sf=1028 # Left superior frontal gyrus
r_cb=47 # Right cerebellar cortex
r_ip=2008 # Right inferior parietal
r_rmf=2027 # Right rostral middle frontal gyrus
r_sf=2028 # Right superior frontal gyrus

# Extract observed timeseries
for i in ${l_cb} ${l_ip} ${l_rmf} ${l_sf} ${r_cb} ${r_ip} ${r_rmf} ${r_sf}; do
    observed_ts=(`3dmaskave -quiet -mask ${seg} -mrange ${i} ${i} ${boldts}`)
    fit_ts=(`3dmaskave -quiet -mask ${seg} -mrange ${i} ${i} ${stem}_fitts.nii.gz`)
    for j in `seq 0 $((${#observed_ts[@]}-1))`; do
        echo "${i},${j},${observed_ts[$j]},Observed"
    done
    for j in `seq 0 $((${#fit_ts[@]}-1))`; do
        echo "${i},${j},${fit_ts[$j]},Fit"
    done
done > ${stem}_dt.csv

rcmd="library(data.table); library(ggplot2);
lut <- data.table(read.csv('FreeSurferColorLUT.csv',comment.char = '#'));
ff<-Sys.glob('*"${stem}"*dt.csv');
for (f in ff) {
    dt <- fread(f);
    names(dt) <- c('Number','Time','Value','Type');
    dt <- merge(dt, lut, by = 'Number', all.x = TRUE, all.y = FALSE);
    dt[, Hemisphere := 'Left'];
    dt[grepl('Right',Name) | grepl('rh',Name), Hemisphere := 'Right'];
    dt[,Type := factor(Type, levels = c('Observed','Fit'))];
    dt[,Region := tolower(Name)][, Region := gsub('ctx-lh-','',gsub('ctx-rh-','',gsub('left-','',gsub('right-','',Region))))];
    dt[,Region := gsub('cerebellum-cortex','cb',gsub('inferiorparietal','ipl',
        gsub('rostralmiddlefrontal','rmfg',gsub('superiorfrontal','sfg',Region))))];
    dt[,ZValue := scale(Value), by = c('Name','Type')];
    p <- ggplot(data = dt, aes(x = Time, y = ZValue)) +
        geom_line(aes(color = Region, linetype = Type)) +
        facet_grid(rows = vars(Region),cols = vars(Hemisphere));
    ggsave(plot = p, filename = paste(gsub('_dt.csv','',f),'timeplot.pdf',sep='_'), width = 11, height = 8.5)
}"

Rscript -e "${rcmd}"
