#######################################    MODIS processing   #######################################
############################  QC Flags processing related functions #######################################
#This script contains functions to help the processing of QC flags for MODIS.
#The current available products are:
# - reflectance (MOD09).       
# - land surface temperature
# - NDVI 
#
#AUTHORS: Benoit Parmentier                                             
#DATE CREATED: 02/23/2017 
#DATE MODIFIED: 02/23/2018
#Version: 1

#PROJECT: General use
#TO DO:
#
#COMMIT: first commit for general modis flag processing functions
#

#################################################################################################

library(sp)
library(raster)
library(rgdal)
require(rgeos)
library(BMS) #contains hex2bin and bin2hex
library(bitops)
require(RCurl)
require(stringr)
require(XML)
library(lubridate)
library(miscFuncs) #contains binary/bit processing helper functions
library(data.table)

################### list of functions

#[1] convert_decimal_to_uint32
#[2] convert_to_decimal
#[3] extract_qc_bit_info
#[4] generate_mask_from_qc_layer
#[5] generate_qc_MODIS_reflectance_MOD09_table
#[6] generate_qc_val_from_int32_reflectance
#[7] screen_qc_bitNo

########### Functions 


convert_decimal_to_uint32 <- function(x){
  bin_val <- bin(x)
  bin_val <- as.numeric(as.logical(bin_val))
  
  if(length(bin_val)< 32){
    add_zero <- 32-length(bin_val) 
  }
  
  bin_val <- c(rep(0,add_zero),bin_val)
  
  return(bin_val)
}

extract_qc_bit_info <- function(bit_range_processed,bin_val){
  #
  start_bit <- as.integer(unlist(strsplit(bit_range_processed,"-"))[1]) +1 #start at 1 in R
  end_bit <- as.integer(unlist(strsplit(bit_range_processed,"-"))[2]) +1
  bin_val_extracted <- bin_val[start_bit:end_bit] # corrected produced at less than ...
  bitNo <- paste(bit_range_processed,collapse = "-")
  bin_val_extracted <- paste(as.character(bin_val_extracted),collapse = "")
  #test <- paste(test,collapse="")
  #bin_val_extracted <- as.character(bin_val_extracted)
  #data.frame(bitNo=bit_range_processed,bin_val_extracted)
  df_bit_qc_info <-data.frame(bitNo=bit_range_processed,bin_val_extracted)
  return(df_bit_qc_info)
}

### This is little endian?
convert_to_decimal <- function(bin_val){
  n <- length(bin_val)
  vals<- lapply(1:n,function(i,coef){coef[i]*2^(n-i)},coef=bin_val)
  sum(unlist(vals))
}

screen_qc_bitNo <- function(qc_val,qc_table_modis_selected){
  
  unique_bitNo  <- unique(qc_table_modis_selected$bitNo)
  
  list_match_val <- vector("list",length=nrow(qc_val))
  #for(i in 1:length(unique_bitNo)){
  for(i in 1:nrow(qc_val)){
    #bitNo_val <- qc_table_modis_selected$bitNo[1]
    #bitNo_val <- unique_bitNo[i]
    bitNo_val <- qc_val$bitNo[i]
    list_match_val[[i]] <- qc_val[qc_val$bitNo==bitNo_val,2]%in%qc_table_modis_selected[qc_table_modis_selected$bitNo==bitNo_val,c("BitComb")]
  }
  qc_val$screen_qc <- as.numeric(list_match_val)
  sum_val <- sum(qc_val$screen_qc)
  
  if(sum_val==nrow(qc_val)){
    mask_val <- 0 #do not mask, keep value
  }else{
    mask_val <- 0 #mask
  }
  
  obj_screen_qc_bitNo <- list(qc_val,mask_val)
  names(obj_screen_qc_bitNo) <- c("qc_val","mask_val")
  
  return(obj_screen_qc_bitNo)
}

generate_qc_MODIS_reflectance_MOD09_table <- function(){
  #This function generates a MODIS quality flag table based on the information
  #from LPDAAC:
  #https://lpdaac.usgs.gov/dataset_discovery/modis/modis_products_table/mod09a1
  #AUTHORS: Benoit Parmentier
  #CREATED: 02/23/2018
  #MODIFIED: 02/23/2018
  #
  
  ######## Start ######
  
  #qc_table_modis <- data.table(bitNo=NA,param_name=NA,BitComb=NA,Sur_refl_qc_500m=NA)
  qc_table_modis <- data.frame(bitNo=NA,param_name=NA,BitComb=NA,Sur_refl_qc_500m=NA)
  ### Make this a function
  ### now add band quality
  band_no <- 1
  list_band_no <- 1:7
  list_qc_table_modis <- vector("list",length=length(list_band_no))
  start_bit <- 0
  i <- 1
  for(i in 1:length(list_band_no)){
    band_no <- list_band_no[i]
    if(i==1){
      start_bit <- 2
    }else{
      start_bit <- end_bit + 1
    }
    #start_bit <- 2
    end_bit <- start_bit + 3 
    bit_range <- paste(start_bit,end_bit,sep="-")
    qc_table_modis[1:9,c("bitNo")] <- rep(bit_range,9) 
    
    qc_table_modis[1:9,c("param_name")] <- rep(paste("band",band_no,"quality four bit range"),9) 
    qc_table_modis[1:9,c("BitComb")] <- c("0000","1000","1001","1010","1011","1100","1101","1110","1111") 
    qc_table_modis[1:9,c("Sur_refl_qc_500m")] <- c("highest quality",
                                                   "dead detector; data interpolated in L1B",
                                                   "solar zenith >=86 degrees",
                                                   "solar zenith >=85 degrees and < 86 degrees",
                                                   "missing input",
                                                   "internal constant used in place of climatological data for at least one atmospheric constant",
                                                   "correction out of bounds pixel constrained to extreme allowable value",
                                                   "L1B data faulty",
                                                   "not processed due to deep ocean or clouds") 
    list_qc_table_modis[[i]] <- qc_table_modis
  }
  
  qc_modis_table_bands <- do.call(rbind,list_qc_table_modis)
  #View(qc_modis_table_bands)
  
  qc_table_modis_modland <- data.frame(bitNo=NA,param_name=NA,BitComb=NA,Sur_refl_qc_500m=NA)
  
  qc_table_modis_modland[1:4,c("bitNo")] <- rep("0-1",4) 
  qc_table_modis_modland[1:4,c("param_name")] <- rep("MODLAND QA bits",4) 
  qc_table_modis_modland[1:4,c("BitComb")] <- c("00","01","10","11") 
  qc_table_modis_modland[1:4,c("Sur_refl_qc_500m")] <- c("corrected product produced at ideal quality all bands",
                                                         "corrected product produced at less than ideal quality some or all bands",
                                                         "corrected product not produced due to cloud effects all bands",
                                                         "corrected producted not produced due to other reasons some or all bands may be fill value [Note that a value of (11) overrides a value of (01)]") 
  
  qc_table_modis_other <- data.frame(bitNo=NA,param_name=NA,BitComb=NA,Sur_refl_qc_500m=NA)
  qc_table_modis_other[1:4,c("bitNo")] <- c(rep("30-30",2),
                                            rep("31-31",2))
  qc_table_modis_other[1:4,c("param_name")] <- c(rep("atmospheric correction performed",2),
                                                 rep("adjacency correction performed",2))
  qc_table_modis_other[1:4,c("BitComb")] <- c("1","0","1","0") 
  qc_table_modis_other[1:4,c("Sur_refl_qc_500m")] <- c("yes","no","yes","no") 
  
  #qc_table_modis <- rbind(qc_table_modis_modland,qc_modis_table_bands)
  qc_table_modis <- rbind(qc_table_modis_modland,qc_modis_table_bands,qc_table_modis_other)
  
  #View(qc_table_modis)
  
  write.table(qc_table_modis,file=file.path(out_dir,"qc_table_modis.txt"),sep=",")
  return(qc_table_modis)
}

generate_qc_val_from_int32_reflectance <- function(val,bit_range_qc){
  #
  #
  
  #i <- 1
  #val <- unique_vals[i]
  
  bin_val <- convert_decimal_to_uint32(val)
  convert_to_decimal(bin_val)
  
  test_bin_val_qc <- lapply(bit_range_qc,FUN=extract_qc_bit_info,bin_val=bin_val)
  test_bin_val_qc[[1]]
  
  qc_val <- do.call(rbind,test_bin_val_qc)
  #View(qc_val)
  return(qc_val)
}

## This can be a general function for other qc too
apply_mask_from_qc_layer <- function(i,rast_qc,rast_var,qc_table_modis_selected,NA_flag_val=-9999,rast_mask=T,out_dir=".",out_suffix=""){
  #This function generates and applies a mask based on the QC layer information
  #Description of the QC table is available from LPDAAC:
  #https://lpdaac.usgs.gov/dataset_discovery/modis/modis_products_table/mod09a1
  #AUTHORS: Benoit Parmentier
  #CREATED: 02/23/2018
  #MODIFIED: 02/23/2018
  
  ### Begin function ###
  
  if(!file.exists(out_dir)){
    dir.create(out_dir)
  }
  
  rast_qc <- rast_qc[[i]]
  rast_var <- rast_var[[i]]
  
  #if(class(r_qc)=="character"){
  #  r_qc <- raster(r_qc)
  #}
  #if(class(r_qc)=="character"){
  #  r_var <- raster(r_var)
  #}  
  
  if(is.character(rast_qc)==TRUE){
    rast_name_qc <- rast_qc
    rast_qc <-raster(rast_qc)
  }else{
    rast_name_qc <- filename(rast_qc)
  }
  
  if(is.character(rast_var)==TRUE){
    rast_name_var <- rast_var
    rast_var<-raster(rast_var)
  }else{
    rast_name_var <- filename(rast_var)
  }
  
  unique_vals <- unique(rast_qc) #first get unique values
  
  ### Do this for unique value 1:
  #debug(generate_qc_val_from_int32_reflectance)
  #qc_val <- generate_qc_val_from_int32_reflectance(unique_vals)
  #browser()
  #unique_bit_range <- unique(qc_table_modis$bitNo)
  bit_range_qc <- unique(qc_table_modis$bitNo) #specific bit range to use to interpret binary
  
  list_qc_val <- lapply(unique_vals,FUN=generate_qc_val_from_int32_reflectance,bit_range_qc)
  #length(list_qc_val)
  length(unique_vals)
  
  ### Find if need to mask the values:
  #### Now compare:
  
  #debug(screen_qc_bitNo)
  #test <- screen_qc_bitNo(list_qc_val[[1]],qc_table_modis)
  
  list_qc_val_screened <- lapply(list_qc_val,
                                 FUN=screen_qc_bitNo,
                                 qc_table_modis = qc_table_modis)
  names(list_qc_val_screened[[1]])
  rm(list_qc_val)
  
  mask_val <- unlist(lapply(list_qc_val_screened,FUN=function(x){x$mask_val}))
  
  df_qc_val <- data.frame(val=unique_vals,mask_val=mask_val)
  df_qc_val$rc_val <- 1 #create new column with mask val to use
  df_qc_val$rc_val[df_qc_val$mask_val==1] <- NA #if mask_val is 1 then set to NA
  
  ###### Reclassify QC image if necessary:
  
  #qc_mask_filename
  if(sum(df_qc_val$mask_val)==0 & rast_mask==TRUE){
    val <- 1 
    setvalf <- function(x){rep(val,x)}
    r_qc_m <- init(rast_qc, fun=setvalf) # mask layer is all one, nothing to mask
  }
  
  if(sum(df_qc_val$mask_val)> 0 & rast_mask==TRUE){
    r_qc_m <- subs(rast_qc, df_qc_val,by="val",which="rc_val")
    #Use "subs" function to assign NA to values that are masked, column 1 contains the identifiers i.e. values in raster
    #r_qc_m <- subs(r_qc, df_qc_val,by=1,which=3)
  }

  ##### Apply mask:
  
  rast_var_m <- mask(rast_var,r_qc_m)
  
  if(rast_mask==FALSE){  #then only write out variable that is masked out
    raster_name <-basename(sub(extension(rast_name_var),"",rast_name_var))
    raster_name<- paste(raster_name,"_",out_suffix,extension(rast_name_var),sep="")
    
    #### change to compress if format is tif!! add this later...
    #file_format <- extension(rast_name_var)
    
    writeRaster(rast_var_m, 
                NAflag=NA_flag_val,
                filename=file.path(out_dir,raster_name),
                bylayer=FALSE,
                bandorder="BSQ",
                overwrite=TRUE)
    
    ## The Raster and rgdal packages write temporary files on the disk when memory is an issue. This can potential build up
    ## in long  loops and can fill up hard drives resulting in errors. The following  sections removes these files 
    ## as they are created in the loop. This code section  can be transformed into a "clean-up function later on
    ## Start remove
    rm(rast_var)
    tempfiles<-list.files(tempdir(),full.names=T) #GDAL transient files are not removed, only RASTER, tempdir() from R basic
    files_to_remove<-grep(out_suffix,tempfiles,value=T) #list files to remove
    if(length(files_to_remove)>0){
      file.remove(files_to_remove)
    }
    #now remove temp files from raster package located in rasterTmpDir
    removeTmpFiles(h=0) #did not work if h is not set to 0
    ## end of remove section
    return(raster_name)
  }else{ #if keep mask true
    raster_name <-basename(sub(extension(rast_name_var),"",rast_name_var))
    raster_name<- paste(raster_name,"_",out_suffix,extension(rast_name_var),sep="")

    #### change to compress if format is tif!! add this later...
    #file_format <- extension(rast_name_var)
    writeRaster(rast_var_m, 
                NAflag=NA_flag_val,
                filename=file.path(out_dir,raster_name),
                bylayer=FALSE,
                bandorder="BSQ",
                overwrite=TRUE)
    
    raster_name_qc <-basename(sub(extension(rast_name_qc),"",rast_name_qc))
    raster_name_qc <- paste(raster_name_qc,"_","mask","_",out_suffix,extension(rast_name_qc),sep="")
    writeRaster(r_qc_m, NAflag=NA_flag_val,filename=file.path(out_dir,raster_name_qc)
                ,bylayer=FALSE,bandorder="BSQ",overwrite=TRUE)
    r_stack_name <- list(file.path(out_dir,raster_name),file.path(out_dir,raster_name_qc))
    names(r_stack_name) <- c("var","mask")
    
    ## The Raster and rgdal packages write temporary files on the disk when memory is an issue. This can potential build up
    ## in long  loops and can fill up hard drives resulting in errors. The following  sections removes these files 
    ## as they are created in the loop. This code section  can be transformed into a "clean-up function later on
    ## Start remove
    rm(rast_var_m)
    rm(r_qc_m)
    tempfiles<-list.files(tempdir(),full.names=T) #GDAL transient files are not removed
    files_to_remove<-grep(out_suffix,tempfiles,value=T) #list files to remove
    if(length(files_to_remove)>0){
      file.remove(files_to_remove)
    }
    #now remove temp files from raster package located in rasterTmpDir
    removeTmpFiles(h=0) #did not work if h is not set to 0
    ## end of remove section
    return(r_stack_name)
  }
  
  #writeRaster()#as tmp file!!!
  ########Apply mask
  
  mask()
  raster_name <- ""
  writeRaster()
  
  ##### if keep_mask==TRUE
  raster_name <- ""
  writeRaster()
  
  return()
}



screen_for_qc_valid_fun <-function(i,list_param){
  ##Function to assign NA given qc flag values from MODIS or other raster
  #Author: Benoit Parmentier
  #Created On: 09/20/2013
  #Modified On: 10/09/2017
  
  #Parse arguments:
  
  qc_valid <- list_param$qc_valid # valid pixel values as dataframe
  rast_qc <- list_param$rast_qc[i] #raster with integer values reflecting quality flag layer e.g. day qc
  rast_var <- list_param$rast_var[i] #raster with measured/derived variable e.g. day LST
  rast_mask <- list_param$rast_mask #return raster mask as separate layer, if TRUE then raster is written and returned?
  NA_flag_val <- list_param$NA_flag_val #value for NA
  out_dir <- list_param$out_dir #output dir
  out_suffix <- out_suffix # suffix used for raster files written as outputs
  
  #########################
  #### Start script:
  
  if(!file.exists(out_dir)){
    dir.create(out_dir)
  }
  
  if(is.character(rast_qc)==TRUE){
    rast_name_qc <- rast_qc
    rast_qc <-raster(rast_qc)
  }
  if(is.character(rast_var)==TRUE){
    rast_name_var <- rast_var
    rast_var<-raster(rast_var)
  }
  
  f_values <- as.data.frame(freq(rast_qc)) # frequency values in the raster...as a dataframe
  f_values$qc_mask <- as.integer(f_values$value %in% qc_valid) # values that should be masked out
  f_values$qc_mask[f_values$qc_mask==0] <- NA #NA for masked out values
  
  #Use "subs" function to assign NA to values that are masked, column 1 contains the identifiers i.e. values in raster
  r_qc_m <- subs(x=rast_qc,y=f_values,by=1,which=3) #Use column labeled as qc_mask (number 3) to assign value
  rast_var_m <-mask(rast_var,r_qc_m)
  
  if(rast_mask==FALSE){  #then only write out variable that is masked out
    raster_name <-basename(sub(extension(rast_name_var),"",rast_name_var))
    raster_name<- paste(raster_name,"_",out_suffix,extension(rast_name_var),sep="")
    writeRaster(rast_var_m, NAflag=NA_flag_val,filename=file.path(out_dir,raster_name)
                ,bylayer=FALSE,bandorder="BSQ",overwrite=TRUE)
    
    ## The Raster and rgdal packages write temporary files on the disk when memory is an issue. This can potential build up
    ## in long  loops and can fill up hard drives resulting in errors. The following  sections removes these files 
    ## as they are created in the loop. This code section  can be transformed into a "clean-up function later on
    ## Start remove
    rm(rast_var)
    tempfiles<-list.files(tempdir(),full.names=T) #GDAL transient files are not removed, only RASTER, tempdir() from R basic
    files_to_remove<-grep(out_suffix,tempfiles,value=T) #list files to remove
    if(length(files_to_remove)>0){
      file.remove(files_to_remove)
    }
    #now remove temp files from raster package located in rasterTmpDir
    removeTmpFiles(h=0) #did not work if h is not set to 0
    ## end of remove section
    return(raster_name)
  }else{ #if keep mask true
    raster_name <-basename(sub(extension(rast_name_var),"",rast_name_var))
    raster_name<- paste(raster_name,"_",out_suffix,extension(rast_name_var),sep="")
    writeRaster(rast_var_m, NAflag=NA_flag_val,filename=file.path(out_dir,raster_name)
                ,bylayer=FALSE,bandorder="BSQ",overwrite=TRUE)
    raster_name_qc <-basename(sub(extension(rast_name_qc),"",rast_name_qc))
    raster_name_qc <- paste(raster_name_qc,"_","mask","_",out_suffix,extension(rast_name_qc),sep="")
    writeRaster(r_qc_m, NAflag=NA_flag_val,filename=file.path(out_dir,raster_name_qc)
                ,bylayer=FALSE,bandorder="BSQ",overwrite=TRUE)
    r_stack_name <- list(file.path(out_dir,raster_name),file.path(out_dir,raster_name_qc))
    names(r_stack_name) <- c("var","mask")
    
    ## The Raster and rgdal packages write temporary files on the disk when memory is an issue. This can potential build up
    ## in long  loops and can fill up hard drives resulting in errors. The following  sections removes these files 
    ## as they are created in the loop. This code section  can be transformed into a "clean-up function later on
    ## Start remove
    rm(rast_var_m)
    rm(r_qc_m)
    tempfiles<-list.files(tempdir(),full.names=T) #GDAL transient files are not removed
    files_to_remove<-grep(out_suffix,tempfiles,value=T) #list files to remove
    if(length(files_to_remove)>0){
      file.remove(files_to_remove)
    }
    #now remove temp files from raster package located in rasterTmpDir
    removeTmpFiles(h=0) #did not work if h is not set to 0
    ## end of remove section
    return(r_stack_name)
  }
}

################################## End of script  #################################