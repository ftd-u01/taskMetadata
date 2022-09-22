#!/bin/bash
#*************************************************
# Simple block design analysis for HCP working memory tfMRI.
#*************************************************

infile=$1
stem=${infile/_space-T1w_desc-drop10_bold.nii.gz}
wd=`dirname ${infile}`
outdir=${wd}
cd $wd
mask=${stem}_rec-norm_label-GM_mask.nii.gz
ortvec=${stem}_desc-ortvec4_timeseries.tsv

c1='faces_0bk'
c2='places_0bk'
c3='faces_2bk'
c4='places_2bk'

#	-mask ${mask} \
3dDeconvolve \
	-input "$infile" \
	-polort -1 \
	-num_stimts 4 \
	-ortvec ${ortvec} nuis \
	-stim_times 1 ${stem}_"$c1"_times.txt 'BLOCK(27.5,1)' -stim_label 1 "$c1" \
	-stim_times 2 ${stem}_"$c2"_times.txt 'BLOCK(27.5,1)' -stim_label 2 "$c2" \
	-stim_times 3 ${stem}_"$c3"_times.txt 'BLOCK(27.5,1)' -stim_label 3 "$c3" \
	-stim_times 4 ${stem}_"$c4"_times.txt 'BLOCK(27.5,1)' -stim_label 4 "$c4" \
    -iresp 1 ${stem}_"$c1"_iresp.nii.gz \
    -iresp 2 ${stem}_"$c2"_iresp.nii.gz \
    -iresp 3 ${stem}_"$c3"_iresp.nii.gz \
    -iresp 4 ${stem}_"$c4"_iresp.nii.gz \
	-num_glt 4 \
	-gltsym 'SYM: +faces_2bk +places_2bk +faces_0bk +places_0bk' -glt_label 1 'task_vs_rest' \
	-gltsym 'SYM: +faces_2bk +places_2bk -faces_0bk -places_0bk' -glt_label 2 'wm_load' \
	-gltsym 'SYM: +faces_2bk -places_2bk +faces_0bk -places_0bk' -glt_label 3 'faces' \
	-gltsym 'SYM: -faces_2bk +places_2bk -faces_0bk +places_0bk' -glt_label 4 'places' \
	-fout -rout -tout \
	-fitts ${stem}_fitts.nii.gz \
	-x1D "$outdir"/"$stem".xmat.1D -xjpeg "$stem"_X.jpg \
	-xsave "$stem".xsave \
	-jobs 1 \
	-overwrite \
	-bucket "$stem"_block.nii.gz
