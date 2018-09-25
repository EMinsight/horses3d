!
!//////////////////////////////////////////////////////
!
!   @File:    main.f90
!   @Author:  Juan Manzanero (juan.manzanero@upm.es)
!   @Created: Sun Dec 24 15:18:48 2017
!   @Last revision date: Tue Sep 25 10:03:25 2018
!   @Last revision author: Andrés Rueda (am.rueda@upm.es)
!   @Last revision commit: f80714f4c78c40aeae2f260a53c2dd6437a97038
!
!//////////////////////////////////////////////////////
!
program main
   use SMConstants
   use MeshTests
   use MeshConsistencySetup
   USE TestSuiteManagerClass
   use NodalStorageClass
   use SharedBCModule
   use MPI_Process_Info
   use BoundaryConditions,    only: BCs
   use FreeSlipWallBCClass,   only: FreeSlipWallBC_t
   use InterpolationMatrices, only: Initialize_InterpolationMatrices, Finalize_InterpolationMatrices
   implicit none
   TYPE(TestSuiteManager) :: testSuite
   INTEGER                :: numberOfFailures
   integer                :: i
   integer, parameter     :: Nmax = 40

   call MPI_Process % Init
   
   CALL testSuite % init()
   
   call InitializeNodalStorage(GAUSS,Nmax)
   call Initialize_InterpolationMatrices(Nmax)
   CALL ConstructSharedBCModule
   allocate(BCs(12))
   do i = 1, 12
      allocate(FreeSlipWallBC_t    :: BCs(i) % bc) 
      select type(bc => BCs(i) % bc)
      type is (FreeSlipWallBC_t)
      bc % BCType = "freeslipwall"
      bc % isAdiabatic = .true.
      bc % kWallType = 0.0_RP
      end select
   end do

   do i = 1, no_of_meshFiles
      call testSuite % addTestSubroutineWithName(OpenNextMesh,"Open next mesh: " // trim(meshFileNames(i)))
      call testSuite % addTestSubroutineWithName(CheckVolume,"Mesh volume: " // trim(meshFileNames(i)))
      call testSuite % addTestSubroutineWithName(CheckZoneSurfaces,"Zone surfaces: " // trim(meshFileNames(i)))
      call testSuite % addTestSubroutineWithName(CheckCoordinatesConsistency,&
                  "Mapping coordinates interpolation consistency: " // trim(meshFileNames(i)))
      call testSuite % addTestSubroutineWithName(CheckNormalConsistency,&
                  "Consistency in the normal vectors: " // trim(meshFileNames(i)))
      call testSuite % addTestSubroutineWithName(CheckScalConsistency,&
                  "Consistency in the surface Jacobians: " // trim(meshFileNames(i)))

   end do

   CALL testSuite % performTests(numberOfFailures)
   CALL testSuite % finalize()
   
   call DestructGlobalNodalStorage()
   call Finalize_InterpolationMatrices
   
   IF(numberOfFailures > 0)   STOP 99

end program main
