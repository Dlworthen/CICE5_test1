;************************************************
; These files are loaded by default in NCL V6.2.0 and newer
; load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
; load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl" 

  load "$NCARG_ROOT/lib/ncarg/nclscripts/contrib/cd_string.ncl"

; Denise.Worthen@noaa.gov

; this script is based on a script developed by Dave Baily (dbailey@ucar.edu)
; and Xingren Wu (xingren.wu@noaa.gov) to convert a SIS restart file to 
; CICE5 with regridding from 1/2 degree tripolar grid to 1/4 degree 
;
; this script assumes the tiled SIS2 restart files have been combined
; into a single tile restart file using mppncombine:
; e.g.: ./mppnccombine -m -v -f ice_model.res.nc
;
; both SIS2 and CICE5 use 5 ice thickness categories; these thickness 
; categories are different between the models
; SIS2 uses : 1e-10, 0.1, 0.3, 0.7, 1.1 (source: Travis Sluka)
; CICE5 uses (kcatbound=0): 0, 0.64, 1.39, 2.47, 4.57
; the script associates the thickness categories between SIS2 and CICE5 1:1
; ignoring the differences in category thickness definitions
;
; this code is a batch job version of the conversion which will
; list all files and loop over each
;************************************************
begin

; define some constants
  saltmax = 3.2d0
min_salin = 0.10d0
 depressT = 0.054d0
     nsal = 0.407d0
     msal = 0.573d0
       pi = atan(1.0d0)*4.0d0
     rhoi =  917.d0
     rhos =  330.d0
   cp_ice = 2106.d0
   cp_ocn = 4218.d0
   Lfresh = 3.34d5

;************************************************
; set up for directory names for batch
;************************************************
 
; this script will write the new CICE5 restart into the sis2src directory
;sis2src = "/scratch3/NCEPDEV/stmp1/Denise.Worthen/TESTDA/"
;sis2src = "/scratch3/NCEPDEV/stmp2/Denise.Worthen/CICE5_RESTARTS/"
sis2src = "/scratch3/NCEPDEV/stmp2/Denise.Worthen/CICE5_RESTARTS_NEW/"
cice5src = "/scratch4/NCEPDEV/nems/noscrub/emc.nemspara/RT/FV3-MOM6-CICE5/update-20190219/CICE/"

; specify 1/4 degree tripole resolution; both SIS2 and CICE5 use the same
; MOM6 1/4 degree tripole grid
ni = 1440
nj = 1080

; specify the name of the CICE5 tmask file
ftmaskname = "kmtu_cice_NEMS_mx025.nc"
fmask = addfile(cice5src+ftmaskname,"r")
print("CICE5 mask file used : "+cice5src+ftmaskname)
; retrieve the iceumask; kmt is stored as integer
kmt = fmask->kmt
iceumask = todouble(kmt)

; list the dates available for conversion
dates = systemfunc("ls "+sis2src)
ndates = dimsizes(dates)
print(dates)

;if(1 .eq. 0)then
;************************************************
; loop over all dates in sis2src which contain
; a SIS2 restartfile
;************************************************

;nd = 10-1
nd = 1
;do  nd = 0,ndates-1

 cdate = dates(nd) 
 ; specify the name of the SIS2 restart file
 finname=cdate+"/mom6_da/ice_model.res.nc"

 if (isfilepresent(sis2src+finname))
  fin  = addfile(sis2src+finname,"r")
  print("SIS2 file being converted : "+sis2src+finname)

  ; specify the name of the new CICE5 restart file
  foutname=cdate+"/mom6_da/cice5_model_0.25.res_"+cdate+".nc"
  ; get output file ready
  system("/bin/rm -f "+sis2src+foutname)
  fout = addfile(sis2src+foutname,"c")
  print("CICE5 file being created : "+sis2src+foutname)

  ; obtain the number of categories 
  ; specify the number of layers 
  ; note that part_size includes the first category as open water
  ; both SIS2 and CICE5 use a single snow layer

  sis2dims = dimsizes(fin->part_size)
  ncat = sis2dims(1) - 1
  ; 1 = sis2, 2 = cice55
  nilyr1 = 4
  nilyr2 = 7
  nsnwlyr = 1

  print("SIS2 input file with ncat = "+ncat+" and nlayers = "+nilyr1)
  print("CICE5 output file with ncat = "+ncat+" and nlayers = "+nilyr2)

;************************************************
;define an arbitray axis to linearly interpolate 
;between SIS2's nilyr1 and CICE5's nilyr2
;************************************************

sdelh = 1.0/nilyr1
cdelh = 1.0/nilyr2

sis2x = fspan(sdelh/2.0,1.0-(sdelh/2.0),nilyr1)
cic5x = fspan(cdelh/2.0,1.0-(cdelh/2.0),nilyr2)
;print("layer axis defined for SIS2  ")
;print(sis2x)
;print("  ")
;print("layer axis defined for CICE5 ")
;print(cic5x)

; if use linlog = -1, intp will linearly interpolate with extrapolation
; if use linit1, then the top and bottom values must be filled
linlog = -1
use_intp = True
use_lint = False

;************************************************
; Define new CICE5 variables
;************************************************

   aicen = new((/ncat,nj,ni/),double)
; layer variables
    qice = new((/nilyr2,ncat,nj,ni/),double)
    sice = new((/nilyr2,ncat,nj,ni/),double)
     Tin = new((/nilyr2,ncat,nj,ni/),double)

   aicen = 0.0
    qice = 0.0
    sice = 0.0
     Tin = 0.0

;************************************************
; Retrieve SIS2 variables 
; SIS2 variables are stored with time dimension
;************************************************

  ; these variables have no categories or layers
    uvel = fin->u_ice_C(0,:,:)
    vvel = fin->v_ice_C(0,:,:)
  coszen = fin->coszen(0,:,:)
   swvdr = fin->flux_sw_vis_dir(0,:,:)
   swvdf = fin->flux_sw_vis_dif(0,:,:)
   swidr = fin->flux_sw_nir_dir(0,:,:)
   swidf = fin->flux_sw_nir_dif(0,:,:)

  ; these variables depend on categories, not 
  ; including open water
   vicen = fin->h_ice(0,:,:,:)
   vsnon = fin->h_snow(0,:,:,:)
  ; T_skin in degC
   Tsfcn = fin->T_skin(0,:,:,:)
  ; snow enthalpy, only 1 snow layer for both SIS2 and CICE5
    qsno = fin->enth_snow(0,:,:,:,:)*rhos
  ;print(dimsizes(vicen))

  ; the SIS2 category ice concentrations
part_size = fin->part_size(0,:,:,:)

; SIS2 enthalpy in J/kg (nilayr1,ncat,nj,ni)
; convert to J/m3
sis2_qice = rhoi*(fin->enth_ice(0,:,:,:,:))

do k = 0,ncat-1
; ice concentration from part_size; k+1 skips the open 
; water category for SIS2
   aicen(k,:,:) = part_size(k+1,:,:)
end do

;************************************************
; linearly interpolate enthalpy between SIS2 4 
; layers and CICE5 7 layers 
;************************************************

do k = 0,ncat-1
 do j = 0,nj-1
  do i = 0,ni-1
   if(kmt(j,i) .eq. 1)then
    qs = sis2_qice(:,k,j,i)
    if(use_lint)
     qc = linint1(sis2x,qs,False,cic5x,0)
     ;fix the top and bottom
     qice(       0,k,j,i) = qice(       1,k,j,i)
     qice(nilyr2-1,k,j,i) = qice(nilyr2-2,k,j,i)
    else
     qc = int2p(sis2x,qs,cic5x,linlog)
     qice(:,k,j,i) = qc
    end if
   end if
  end do
 end do
end do
;ii = 706-1
;jj = 155-1
;print("SIS2 Qice")
;print(sis2x(:)+"   "+sis2_qice(:,0,jj,ii))
;print("CICE5 Qice")
;print(cic5x(:)+"   "+qice(:,0,jj,ii))
;
; get the right units on vicen and vsnon (m)
vicen = aicen*vicen/rhoi
vsnon = aicen*vsnon/rhos

;************************************************
; ? a reasonable salinity profile
;************************************************

salinz = new((/nilyr2/),double)
do l = 0,nilyr2-1
            zn = (int2dble(l+1)-0.5d0)/int2dble(nilyr2)
     salinz(l) = (saltmax/2.d0)*(1.d0-cos(pi*zn^(nsal/(msal+zn))))
;     salinz(l) = where(salinz(l) .lt. min_salin, min_salin, salinz(l))
; replace SIS2 constant profile
 sice(l,:,:,:) = salinz(l)
end do
;print(salinz)
;print(-salinz*depressT)
Tmltz = salinz / (-18.48 + (0.01848*salinz))
;print(Tmltz)

; get Tin from inverting qice eqn in original script
do l = 0,nilyr2-1
   Tin(l,:,:,:) = (qice(l,:,:,:) + rhoi*Lfresh)/(rhoi*cp_ice)
   Tin(l,:,:,:) = where(Tin(l,:,:,:) .gt. Tmltz(l), Tmltz(l), Tin(l,:,:,:))
end do
Tin = where(Tin .lt.    0.d0, Tin, 0.d0)
Tin = where(Tin .ge. -100.d0, Tin, 0.d0)

;ii = 706-1
;jj = 155-1
;print("CICE5 Tin")
;print(cic5x(:)+"   "+Tin(:,0,jj,ii))

do l = 0,nilyr2-1
   qice(l,:,:,:) = rhoi*cp_ice*Tin(l,:,:,:) - rhoi*Lfresh
   qice(l,:,:,:) = where(vicen .gt. 0.d0, qice(l,:,:,:), 0.d0)
end do

;ii = 706-1
;jj = 155-1
;print("CICE5 Qice")
;print(cic5x(:)+"   "+qice(:,0,jj,ii))

do l=0,nsnwlyr-1
   qsno(l,:,:,:) = -rhos*(Lfresh - cp_ice*Tsfcn(:,:,:))
   qsno(l,:,:,:) = where(vsnon .gt. 0.d0, qsno(l,:,:,:), 0.0)
end do

qice = where(ismissing(qice), 0.0, qice)
qsno = where(ismissing(qsno), 0.0, qsno)

;************************************************
; SIS2 restart has missing values but no attribute for it
; set the fill value for uvel and use it to replace missing values
;************************************************

   uvel@_FillValue = default_fillvalue("double")

    vvel = where(ismissing(uvel), 0.0d0,   vvel)
  coszen = where(ismissing(uvel), 0.0d0, coszen)
   swvdr = where(ismissing(uvel), 0.0d0,  swvdr)
   swvdf = where(ismissing(uvel), 0.0d0,  swvdf)
   swidr = where(ismissing(uvel), 0.0d0,  swidr)
   swidf = where(ismissing(uvel), 0.0d0,  swidf)

  do k = 0,ncat-1
   aicen(k,:,:) = where(ismissing(uvel), 0.0d0, aicen(k,:,:))
   vicen(k,:,:) = where(ismissing(uvel), 0.0d0, vicen(k,:,:))
   vsnon(k,:,:) = where(ismissing(uvel), 0.0d0, vsnon(k,:,:))
   Tsfcn(k,:,:) = where(ismissing(uvel), 0.0d0, Tsfcn(k,:,:))
   do l = 0,nsnwlyr-1
    qsno(l,k,:,:) = where(ismissing(uvel), 0.0d0,  qsno(l,k,:,:))
   end do
   do l = 0,nilyr2-1
    qice(l,k,:,:) = where(ismissing(uvel), 0.0d0,  qice(l,k,:,:))
    sice(l,k,:,:) = where(ismissing(uvel), 0.0d0,  sice(l,k,:,:))
     Tin(l,k,:,:) = where(ismissing(uvel), 0.0d0,   Tin(l,k,:,:))
   end do
  end do
  
; remove uvel missing value
  uvel = where(ismissing(uvel), 0.0d0,   uvel)

; remove non-ice points
   uvel = where(dim_sum_n(aicen,0) .eq. 0.0d0, 0.0d0,  uvel)
   vvel = where(dim_sum_n(aicen,0) .eq. 0.0d0, 0.0d0,  vvel)

aice = conform_dims(dimsizes(vicen),dim_sum_n(aicen,0),(/1,2/))

do k = 0,ncat-1
  vicen = where(aice .eq. 0.0d0, 0.0d0, vicen)
  vsnon = where(aice .eq. 0.0d0, 0.0d0, vsnon)
  Tsfcn = where(aice .eq. 0.0d0, 0.0d0, Tsfcn)
end do
;************************************************
; Initialize these CICE5 variables to zero
;************************************************

  scale_factor = uvel*0.
      strocnxT = uvel*0.
      strocnyT = uvel*0.
     frz_onset = uvel*0.
  ; set all stresses as zero (no longer directly comparable form from SIS2) 
     stressp_1 = uvel*0.
     stressp_2 = uvel*0.
     stressp_3 = uvel*0.
     stressp_4 = uvel*0.
     stressm_1 = uvel*0.
     stressm_2 = uvel*0.
     stressm_3 = uvel*0.
     stressm_4 = uvel*0.
    stress12_1 = uvel*0.
    stress12_2 = uvel*0.
    stress12_3 = uvel*0.
    stress12_4 = uvel*0.

;************************************************
; dump to netcdf follows original script
;************************************************

; set a flag to skip writing the file while debugging
write_the_file = "no"
if(write_the_file .eq. "yes")then

setfileoption("nc","format","LargeFile")

setfileoption(fout,"DefineMode",True)

dimNames = (/"nilyr","ncat","nj","ni"/)
dimSizes = (/nilyr2,ncat,nj,ni/)
dimUnlim = (/False,False,False,False/)
filedimdef(fout,dimNames,dimSizes,dimUnlim)

filevardef(fout,"aicen",typeof(aicen),(/"ncat","nj","ni"/))
filevardef(fout,"vicen",typeof(vicen),(/"ncat","nj","ni"/))
filevardef(fout,"vsnon",typeof(vsnon),(/"ncat","nj","ni"/))
filevardef(fout,"Tsfcn",typeof(Tsfcn),(/"ncat","nj","ni"/))
filevardef(fout,"uvel",typeof(uvel),(/"nj","ni"/))
filevardef(fout,"vvel",typeof(vvel),(/"nj","ni"/))
filevardef(fout,"scale_factor",typeof(scale_factor),(/"nj","ni"/))
filevardef(fout,"coszen",typeof(coszen),(/"nj","ni"/))
filevardef(fout,"swvdr",typeof(swvdr),(/"nj","ni"/))
filevardef(fout,"swvdf",typeof(swvdf),(/"nj","ni"/))
filevardef(fout,"swidr",typeof(swidr),(/"nj","ni"/))
filevardef(fout,"swidf",typeof(swidf),(/"nj","ni"/))
filevardef(fout,"strocnxT",typeof(strocnxT),(/"nj","ni"/))
filevardef(fout,"strocnyT",typeof(strocnyT),(/"nj","ni"/))
filevardef(fout,"stressp_1",typeof(stressp_1),(/"nj","ni"/))
filevardef(fout,"stressp_2",typeof(stressp_2),(/"nj","ni"/))
filevardef(fout,"stressp_3",typeof(stressp_3),(/"nj","ni"/))
filevardef(fout,"stressp_4",typeof(stressp_4),(/"nj","ni"/))
filevardef(fout,"stressm_1",typeof(stressm_1),(/"nj","ni"/))
filevardef(fout,"stressm_2",typeof(stressm_2),(/"nj","ni"/))
filevardef(fout,"stressm_3",typeof(stressm_3),(/"nj","ni"/))
filevardef(fout,"stressm_4",typeof(stressm_4),(/"nj","ni"/))
filevardef(fout,"stress12_1",typeof(stress12_1),(/"nj","ni"/))
filevardef(fout,"stress12_2",typeof(stress12_2),(/"nj","ni"/))
filevardef(fout,"stress12_3",typeof(stress12_3),(/"nj","ni"/))
filevardef(fout,"stress12_4",typeof(stress12_4),(/"nj","ni"/))
filevardef(fout,"iceumask",typeof(iceumask),(/"nj","ni"/))

filevardef(fout,"qice001",typeof(qice),(/"ncat","nj","ni"/))
filevardef(fout,"qice002",typeof(qice),(/"ncat","nj","ni"/))
filevardef(fout,"qice003",typeof(qice),(/"ncat","nj","ni"/))
filevardef(fout,"qice004",typeof(qice),(/"ncat","nj","ni"/))
filevardef(fout,"qice005",typeof(qice),(/"ncat","nj","ni"/))
filevardef(fout,"qice006",typeof(qice),(/"ncat","nj","ni"/))
filevardef(fout,"qice007",typeof(qice),(/"ncat","nj","ni"/))
filevardef(fout,"sice001",typeof(sice),(/"ncat","nj","ni"/))
filevardef(fout,"sice002",typeof(sice),(/"ncat","nj","ni"/))
filevardef(fout,"sice003",typeof(sice),(/"ncat","nj","ni"/))
filevardef(fout,"sice004",typeof(sice),(/"ncat","nj","ni"/))
filevardef(fout,"sice005",typeof(sice),(/"ncat","nj","ni"/))
filevardef(fout,"sice006",typeof(sice),(/"ncat","nj","ni"/))
filevardef(fout,"sice007",typeof(sice),(/"ncat","nj","ni"/))
filevardef(fout,"qsno001",typeof(qsno),(/"ncat","nj","ni"/))
filevardef(fout,"frz_onset",typeof(frz_onset),(/"nj","ni"/))
filevardef(fout,"Tin",typeof(Tin),(/"nilyr","ncat","nj","ni"/))

setfileoption(fout,"DefineMode",False)

; setfileoption(fout,"DefineMode",True)

; strtWrt = systemfunc("date")
; print (strtWrt)
print ("writing aicen")
fout->aicen = (/aicen/)
print ("writing vicen")
fout->vicen = (/vicen/)
print ("writing vsnon")
fout->vsnon = (/vsnon/)
print ("writing Tsfcn")
fout->Tsfcn = (/Tsfcn/)
print ("writing uvel")
fout->uvel = (/uvel/)
print ("writing vvel")
fout->vvel = (/vvel/)
print ("writing scale_factor")
fout->scale_factor = (/scale_factor/)
print ("writing coszen")
fout->coszen = (/coszen/)
print ("writing swvdr")
fout->swvdr = (/swvdr/)
print ("writing swvdf")
fout->swvdf = (/swvdf/)
;
; wallClockElapseTime(strtWrt, "write 10 records", 0)

print ("writing swidr")
fout->swidr = (/swidr/)
print ("writing swidf")
fout->swidf = (/swidf/)
print ("writing strocnxT")
fout->strocnxT = (/strocnxT/)
print ("writing strocnyT")
fout->strocnyT = (/strocnyT/)
print ("writing stressp_1")
fout->stressp_1 = (/stressp_1/)
print ("writing stressp_2")
fout->stressp_2 = (/stressp_2/)
print ("writing stressp_3")
fout->stressp_3 = (/stressp_3/)
print ("writing stressp_4")
fout->stressp_4 = (/stressp_4/)
print ("writing stressm_1")
fout->stressm_1 = (/stressm_1/)
print ("writing stressm_2")
fout->stressm_2 = (/stressm_2/)
print ("writing stressm_3")
fout->stressm_3 = (/stressm_3/)
print ("writing stressm_4")
fout->stressm_4 = (/stressm_4/)
print ("writing stress12_4")
fout->stress12_4 = (/stress12_4/)
print ("writing stress12_1")
fout->stress12_1 = (/stress12_1/)
print ("writing stress12_2")
fout->stress12_2 = (/stress12_2/)
print ("writing stress12_3")
fout->stress12_3 = (/stress12_3/)
print ("writing iceumask")
fout->iceumask = (/iceumask/)
print ("writing frz_onset")
fout->frz_onset = (/frz_onset/)
print ("writing qice001")
fout->qice001 = (/qice(0,:,:,:)/)
print ("writing qice002")
fout->qice002 = (/qice(1,:,:,:)/)
print ("writing qice003")
fout->qice003 = (/qice(2,:,:,:)/)
print ("writing qice004")
fout->qice004 = (/qice(3,:,:,:)/)
print ("writing qice005")
fout->qice005 = (/qice(4,:,:,:)/)
print ("writing qice006")
fout->qice006 = (/qice(5,:,:,:)/)
print ("writing qice007")
fout->qice007 = (/qice(6,:,:,:)/)
print ("writing Tin")
fout->Tin = (/Tin/)
print ("writing sice001")
fout->sice001 = (/sice(0,:,:,:)/)
print ("writing sice002")
fout->sice002 = (/sice(1,:,:,:)/)
print ("writing sice003")
fout->sice003 = (/sice(2,:,:,:)/)
print ("writing sice004")
fout->sice004 = (/sice(3,:,:,:)/)
print ("writing sice005")
fout->sice005 = (/sice(4,:,:,:)/)
print ("writing sice006")
fout->sice006 = (/sice(5,:,:,:)/)
print ("writing sice007")
fout->sice007 = (/sice(6,:,:,:)/)
print ("writing qsno001")
fout->qsno001 = (/qsno(0,:,:,:)/)

; debugging, write_the_file
end if

  ; clean up 
  delete(fin)
  delete(fout)
  delete(aicen)
  delete(qice)
  delete(sice)
  delete(Tin)
  delete(salinz)
 end if ; file is present
;end do ; ndates
;end if

print ("The END")
exit
end
