!=====================================================================
!
!          S p e c f e m 3 D  G l o b e  V e r s i o n  4 . 0
!          --------------------------------------------------
!
!          Main authors: Dimitri Komatitsch and Jeroen Tromp
!    Seismological Laboratory, California Institute of Technology, USA
!                 and University of Pau / CNRS, France
! (c) California Institute of Technology and University of Pau / CNRS, November 2007
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 2 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
!
!=====================================================================

program combine_vol_data

  ! combines the database files on several slices.
  ! the local database file needs to have been collected onto the frontend (copy_local_database.pl)

  implicit none

  include 'constants.h'
  include 'OUTPUT_FILES/values_from_mesher.h'

  integer,parameter :: MAX_NUM_NODES = 300
  integer  iregion, ir, irs, ire, ires, pfd, efd
  character(len=150) :: sline, arg(6), filename, indir, outdir, prname, dimension_file, command_name
  character(len=150) :: pt_mesh_file1, pt_mesh_file2, mesh_file, em_mesh_file, data_file, topo_file
  integer, dimension(MAX_NUM_NODES) :: node_list, nspec, nglob, npoint, nelement
  integer iproc, num_node, i,j,k,ispec, ios, it, di, dj, dk
  integer np, ne,  njunk
  real(kind=CUSTOM_REAL) data(NGLLX,NGLLY,NGLLZ,NSPEC_CRUST_MANTLE)
  real(kind=CUSTOM_REAL),dimension(NGLOB_CRUST_MANTLE) :: xstore, ystore, zstore
  integer ibool(NGLLX,NGLLY,NGLLZ,NSPEC_CRUST_MANTLE)
  integer num_ibool(NGLOB_CRUST_MANTLE)
  logical mask_ibool(NGLOB_CRUST_MANTLE), HIGH_RESOLUTION_MESH
  real x, y, z, dat
  integer numpoin, iglob, n1, n2, n3, n4, n5, n6, n7, n8
  integer iglob1, iglob2, iglob3, iglob4, iglob5, iglob6, iglob7, iglob8


  do i = 1, 6
    call getarg(i,arg(i))
    if (i < 6 .and. trim(arg(i)) == '') then
      print *, ' '
      print *, ' Usage: xcombine_vol_data slice_list filename input_dir output_dir high/low-resolution [region]'
      print *, '   expect to have the topology and filename.bin(NGLLX,NGLLY,NGLLZ,nspec) already collected to input_dir'
      print *, '   output mesh files (filename_points.mesh, filename_elements.mesh) go to output_dir '
      print *, '   give 0 for low resolution and 1 for high resolution'
      print *, '   if region is not specified, all 3 regions will be collected, otherwise, only collect regions specified'
      stop ' Reenter command line options'
    endif
  enddo

  if (NSPEC_CRUST_MANTLE < NSPEC_OUTER_CORE .or. NSPEC_CRUST_MANTLE < NSPEC_INNER_CORE) &
             stop 'This program needs that NSPEC_CRUST_MANTLE > NSPEC_OUTER_CORE and NSPEC_INNER_CORE'

  ! get region id
  if (trim(arg(6)) == '') then
    iregion  = 0
  else
    read(arg(6),*) iregion
  endif
  if (iregion > 3 .or. iregion < 0) stop 'Iregion = 0,1,2,3'
  if (iregion == 0) then
    irs = 1
    ire = 3
  else
    irs = iregion
    ire = irs
  endif

  ! get slices id
  num_node = 0
  open(unit = 20, file = trim(arg(1)), status = 'unknown',iostat = ios)
  if (ios /= 0) stop 'Error opening file'
  do while (1 == 1)
    read(20,'(a)',iostat=ios) sline
    if (ios /= 0) exit
    read(sline,*,iostat=ios) njunk
    if (ios /= 0) exit
    num_node = num_node + 1
    node_list(num_node) = njunk
  enddo
  close(20)
  print *, 'slice list: '
  print *, node_list(1:num_node)
  print *, ' '

  ! file to collect
  filename = arg(2)

  ! input and output dir
  indir= arg(3)
  outdir = arg(4)

  ! resolution
  read(arg(5),*) ires
  if (ires == 0) then
    HIGH_RESOLUTION_MESH = .false.
    di = NGLLX-1; dj = NGLLY-1; dk = NGLLZ-1
  else
    HIGH_RESOLUTION_MESH = .true.
    di = 1; dj = 1; dk = 1
  endif
  print *, 'resolution ', HIGH_RESOLUTION_MESH

  do ir = irs, ire
    print *, '----------- Region ', ir, '----------------'

    ! open paraview output mesh file
    write(pt_mesh_file1,'(a,i1,a)') trim(outdir)//'/' // 'reg_',ir,'_'//trim(filename)//'_point1.mesh'
    write(pt_mesh_file2,'(a,i1,a)') trim(outdir)//'/' // 'reg_',ir,'_'//trim(filename)//'_point2.mesh'
    write(mesh_file,'(a,i1,a)') trim(outdir)//'/' // 'reg_',ir,'_'//trim(filename)//'.mesh'
    write(em_mesh_file,'(a,i1,a)') trim(outdir)//'/' // 'reg_',ir,'_'//trim(filename)//'_element.mesh'

    call open_file_fd(trim(pt_mesh_file1)//char(0),pfd)
    call open_file_fd(trim(em_mesh_file)//char(0),efd)

    ! figure out total number of points and elements for high-res mesh

    do it = 1, num_node

      iproc = node_list(it)

      print *, 'Reading slice ', iproc
      write(prname,'(a,i6.6,a,i1,a)') trim(indir)//'/proc',iproc,'_reg',ir,'_'

      dimension_file = trim(prname) //'array_dims.txt'
      open(unit = 27,file = trim(dimension_file),status='old',action='read', iostat = ios)
      if (ios /= 0) stop 'Error opening file'
      read(27,*) nspec(it)
      read(27,*) nglob(it)
      close(27)
      if (HIGH_RESOLUTION_MESH) then
        npoint(it) = nglob(it)
        nelement(it) = nspec(it) * (NGLLX-1) * (NGLLY-1) * (NGLLZ-1)
      else
        nelement(it) = nspec(it)
      endif

    enddo

    print *, 'nspec(it) = ', nspec(1:num_node)
    print *, 'nglob(it) = ', nglob(1:num_node)

    call write_integer_fd(efd,sum(nelement(1:num_node)))

    np = 0
    ne = 0

    ! write points information

    do it = 1, num_node

      iproc = node_list(it)

      print *, ' '
      print *, 'Reading slice ', iproc
      write(prname,'(a,i6.6,a,i1,a)') trim(indir)//'/proc',iproc,'_reg',ir,'_'

      ! filename.bin
      data_file = trim(prname) // trim(filename) // '.bin'
      open(unit = 27,file = trim(data_file),status='old',action='read', iostat = ios,form ='unformatted')
      if (ios /= 0) stop 'Error opening file'

      read(27) data(:,:,:,1:nspec(it))
      close(27)
      print *, trim(data_file)

      ! topology file
      topo_file = trim(prname) // 'solver_data_2' // '.bin'
      open(unit = 28,file = trim(topo_file),status='old',action='read', iostat = ios, form='unformatted')
      if (ios /= 0) stop 'Error opening file'

      read(28) xstore(1:nglob(it))
      read(28) ystore(1:nglob(it))
      read(28) zstore(1:nglob(it))
      read(28) ibool(:,:,:,1:nspec(it))
      close(28)
      print *, trim(topo_file)

      mask_ibool(:) = .false.
      num_ibool(:) = 0
      numpoin = 0

      ! write point file
      do ispec=1,nspec(it)
        do k = 1, NGLLZ, dk
          do j = 1, NGLLY, dj
            do i = 1, NGLLX, di
              iglob = ibool(i,j,k,ispec)
              if(.not. mask_ibool(iglob)) then
                numpoin = numpoin + 1
                x = xstore(iglob)
                y = ystore(iglob)
                z = zstore(iglob)
                dat = data(i,j,k,ispec)
                call write_real_fd(pfd,x)
                call write_real_fd(pfd,y)
                call write_real_fd(pfd,z)
                call write_real_fd(pfd,dat)
                mask_ibool(iglob) = .true.
                num_ibool(iglob) = numpoin
              endif
            enddo ! i
          enddo ! j
        enddo ! k
      enddo !ispec

      ! no way to check the number of points for low-res
      if (HIGH_RESOLUTION_MESH .and. numpoin /= npoint(it)) then
        stop 'different number of points (high-res)'
      else if (.not. HIGH_RESOLUTION_MESH) then
        npoint(it) = numpoin
      endif

      ! write elements file
      do ispec = 1, nspec(it)
        do k = 1, NGLLZ-1, dk
          do j = 1, NGLLY-1, dj
            do i = 1, NGLLX-1, di
              iglob1 = ibool(i,j,k,ispec)
              iglob2 = ibool(i+di,j,k,ispec)
              iglob3 = ibool(i+di,j+dj,k,ispec)
              iglob4 = ibool(i,j+dj,k,ispec)
              iglob5 = ibool(i,j,k+dk,ispec)
              iglob6 = ibool(i+di,j,k+dk,ispec)
              iglob7 = ibool(i+di,j+dj,k+dk,ispec)
              iglob8 = ibool(i,j+dj,k+dk,ispec)
              n1 = num_ibool(iglob1)+np-1
              n2 = num_ibool(iglob2)+np-1
              n3 = num_ibool(iglob3)+np-1
              n4 = num_ibool(iglob4)+np-1
              n5 = num_ibool(iglob5)+np-1
              n6 = num_ibool(iglob6)+np-1
              n7 = num_ibool(iglob7)+np-1
              n8 = num_ibool(iglob8)+np-1
              call write_integer_fd(efd,n1)
              call write_integer_fd(efd,n2)
              call write_integer_fd(efd,n3)
              call write_integer_fd(efd,n4)
              call write_integer_fd(efd,n5)
              call write_integer_fd(efd,n6)
              call write_integer_fd(efd,n7)
              call write_integer_fd(efd,n8)
              write(22,'(8i7)') n1,n2,n3,n4,n5,n6,n7,n8
            enddo
          enddo
        enddo
      enddo

      np = np + npoint(it)
      ne = ne + nelement(it)

    enddo  ! all slices for points

    if (np /= sum(npoint(1:num_node)))  stop 'Error: Number of total points are not consistent'
    if (ne /= sum(nelement(1:num_node))) stop 'Error: Number of total elements are not consistent'

    print *, 'Total number of points: ', np
    print *, 'Total number of elements: ', ne

    call close_file_fd(pfd)
    call close_file_fd(efd)

    ! add the critical piece: total number of points
    call open_file_fd(trim(pt_mesh_file2)//char(0),pfd)
    call write_integer_fd(pfd,np)
    call close_file_fd(pfd)

    command_name='cat '//trim(pt_mesh_file2)//' '//trim(pt_mesh_file1)//' '&
               //trim(em_mesh_file)//' > '//trim(mesh_file)
    print *, ' '
    print *, 'cat mesh files: '
    print *, trim(command_name)
    call system(trim(command_name))

  enddo

  print *, 'Done writing mesh files'
  print *, ' '


end program combine_vol_data
