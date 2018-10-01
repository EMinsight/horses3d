!
!////////////////////////////////////////////////////////////////////////
!
!      DGSEMClass.f95
!      Created: 2008-07-12 13:38:26 -0400 
!      By: David Kopriva
!
!      Basic class for the discontinuous Galerkin spectral element
!      solution of conservation laws.
!
!////////////////////////////////////////////////////////////////////////
!
#if defined(NAVIERSTOKES)
#define NNS NCONS
#define NGRADNS NGRAD
#elif defined(INCNS)
#define NNS NINC
#define NGRADNS NINC
#endif

#include "Includes.h"
Module DGSEMClass
   use SMConstants
   USE NodalStorageClass         , only: CurrentNodes, NodalStorage, NodalStorage_t
   use MeshTypes                 , only: HOPRMESH
   use ElementClass
   USE HexMeshClass
   USE PhysicsStorage
   use FluidData
   use FileReadingUtilities      , only: getFileName
#if defined(NAVIERSTOKES)
   USE ManufacturedSolutions
#endif
   use MonitorsClass
   use ParticlesClass
   use Physics
   use ProblemFileFunctions, only: UserDefinedInitialCondition_f
#ifdef _HAS_MPI_
   use mpi
#endif
   
   IMPLICIT NONE

   private
   public   ComputeTimeDerivative_f, DGSem, ConstructDGSem

   public   DestructDGSEM, MaxTimeStep, ComputeMaxResiduals

   TYPE DGSem
      REAL(KIND=RP)                                           :: maxResidual
      integer                                                 :: nodes                 ! Either GAUSS or GAUSLOBATTO
      INTEGER                                                 :: numberOfTimeSteps
      INTEGER                                                 :: NDOF                         ! Number of degrees of freedom
      TYPE(HexMesh)                                           :: mesh
      LOGICAL                                                 :: ManufacturedSol = .FALSE.   ! Use manifactured solutions? default .FALSE.
      type(Monitor_t)                                         :: monitors
#if defined(NAVIERSTOKES) || defined(INCNS)
      type(Particles_t)                                       :: particles
#else
      logical                                                 :: particles
#endif
      contains
         procedure :: construct => ConstructDGSem
         procedure :: destruct  => DestructDGSem
         procedure :: SaveSolutionForRestart
         procedure :: SetInitialCondition => DGSEM_SetInitialCondition
         procedure :: copy                => DGSEM_Assign
         generic   :: assignment(=)       => copy
   END TYPE DGSem

   abstract interface
      SUBROUTINE ComputeTimeDerivative_f( mesh, particles, time, mode )
         use SMConstants
         use HexMeshClass
         use ParticlesClass
         IMPLICIT NONE 
         type(HexMesh), target           :: mesh
#if defined(NAVIERSTOKES) || defined(INCNS)
         type(Particles_t)               :: particles
#else
         logical                         :: particles
#endif
         REAL(KIND=RP)                   :: time
         integer,             intent(in) :: mode
      end subroutine ComputeTimeDerivative_f
   END INTERFACE

   CONTAINS 
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE ConstructDGSem( self, meshFileName_, controlVariables, &
                                 polynomialOrder, Nx_, Ny_, Nz_, success, ChildSem )
      use ReadMeshFile
      use FTValueDictionaryClass
      use mainKeywordsModule
      use StopwatchClass
      use MPI_Process_Info
      use PartitionedMeshClass
      use MeshPartitioning
      IMPLICIT NONE
!
!     --------------------------
!     Constructor for the class.
!     --------------------------
!
      CLASS(DGSem)                       :: self                               !<> Class to be constructed
      character(len=*),         optional :: meshFileName_
      class(FTValueDictionary)           :: controlVariables                   !<  Name of mesh file
      INTEGER, OPTIONAL                  :: polynomialOrder(3)                 !<  Uniform polynomial order
      INTEGER, OPTIONAL, TARGET          :: Nx_(:), Ny_(:), Nz_(:)             !<  Non-uniform polynomial order
      LOGICAL, OPTIONAL                  :: success                            !>  Construction finalized correctly?
      logical, optional                  :: ChildSem                           !<  Is this a (multigrid) child sem?
!
!     ---------------
!     Local variables
!     ---------------
!
      INTEGER                     :: i,j,k,el,bcset                     ! Counters
      INTEGER, POINTER            :: Nx(:), Ny(:), Nz(:)                ! Orders of every element in mesh (used as pointer to use less space)
      integer                     :: NelL(2), NelR(2)
      INTEGER                     :: nTotalElem                              ! Number of elements in mesh
      INTEGER                     :: fUnit
      integer                     :: dir2D
      logical                     :: MeshInnerCurves                    ! The inner survaces of the mesh have curves?
      character(len=*), parameter :: TWOD_OFFSET_DIR_KEY = "2d mesh offset direction"
#if (!defined(NAVIERSTOKES))
      logical, parameter          :: computeGradients = .true.
#endif
      
      if ( present(ChildSem) .and. ChildSem ) self % mesh % child = .TRUE.
      
!
!     Measure preprocessing time
!     --------------------------      
      if (.not. self % mesh % child) then
         call Stopwatch % CreateNewEvent("Preprocessing")
         call Stopwatch % Start("Preprocessing")
      end if
      
      if ( present( meshFileName_ ) ) then
!
!        Mesh file set up by input argument
!        ----------------------------------
         self % mesh % meshFileName = trim(meshFileName_)

      else
!
!        Mesh file set up by controlVariables
!        ------------------------------------
         self % mesh % meshFileName = controlVariables % stringValueForKey(meshFileNameKey, requestedLength = LINE_LENGTH) 

      end if
!
!     ------------------------------
!     Discretization nodes selection
!     ------------------------------
!
      self % nodes = CurrentNodes
!
!     ---------------------------------------
!     Get polynomial orders for every element
!     ---------------------------------------
!
      IF (PRESENT(Nx_) .AND. PRESENT(Ny_) .AND. PRESENT(Nz_)) THEN
         Nx => Nx_
         Ny => Ny_
         Nz => Nz_
         nTotalElem = SIZE(Nx)
      ELSEIF (PRESENT(polynomialOrder)) THEN
         nTotalElem = NumOfElemsFromMeshFile( self % mesh % meshfileName )
         
         ALLOCATE (Nx(nTotalElem),Ny(nTotalElem),Nz(nTotalElem))
         Nx = polynomialOrder(1)
         Ny = polynomialOrder(2)
         Nz = polynomialOrder(3)
      ELSE
         ERROR STOP 'ConstructDGSEM: Polynomial order not specified'
      END IF
      
      if ( max(maxval(Nx),maxval(Ny),maxval(Nz)) /= min(minval(Nx),minval(Ny),minval(Nz)) ) self % mesh % anisotropic = .TRUE.
      
!
!     -------------------------------------------------------------
!     Construct the polynomial storage for the elements in the mesh
!     -------------------------------------------------------------
!
      call NodalStorage(0) % Construct(CurrentNodes, 0)   ! Always construct orders 0 
      call NodalStorage(1) % Construct(CurrentNodes, 1)   ! and 1

      DO k=1, nTotalElem
         call NodalStorage(Nx(k)) % construct( CurrentNodes, Nx(k) )
         call NodalStorage(Ny(k)) % construct( CurrentNodes, Ny(k) )
         call NodalStorage(Nz(k)) % construct( CurrentNodes, Nz(k) )
      END DO
!
!     ------------------
!     Construct the mesh
!     ------------------
!
      if ( controlVariables % containsKey(TWOD_OFFSET_DIR_KEY) ) then
         select case ( controlVariables % stringValueForKey(TWOD_OFFSET_DIR_KEY,1))
         case("x")
            dir2D = 1
         case("y")
            dir2D = 2
         case("z")
            dir2D = 3
         case("3d","3D")
            dir2D = 0
         case default
            print*, "Unrecognized 2D mesh offset direction"
            stop
            errorMessage(STD_OUT)
         end select

      else
         dir2D = 0

      end if
      
      if (controlVariables % containsKey("mesh inner curves")) then
         MeshInnerCurves = controlVariables % logicalValueForKey("mesh inner curves")
      else
         MeshInnerCurves = .true.
      end if
!
!     **********************************************************
!     *                  MPI PREPROCESSING                     *
!     **********************************************************
!
!     Initialization
!     --------------
      call Initialize_MPI_Partitions ( trim(controlVariables % stringValueForKey('partitioning', requestedLength = LINE_LENGTH)) )
!
!     Prepare the processes to receive the partitions
!     -----------------------------------------------
      if ( MPI_Process % doMPIAction ) then
         call RecvPartitionMPI( MeshFileType(self % mesh % meshFileName) == HOPRMESH )
      end if
!
!     Read the mesh by the root rank to perform the partitioning
!     ----------------------------------------------------------
      if ( MPI_Process % doMPIRootAction ) then
!
!        Construct the full mesh
!        -----------------------
         call constructMeshFromFile( self % mesh, self % mesh % meshFileName, CurrentNodes, Nx, Ny, Nz, MeshInnerCurves , dir2D, success )
!
!        Perform the partitioning
!        ------------------------
         call PerformMeshPartitioning  (self % mesh, MPI_Process % nProcs, mpi_allPartitions)
!
!        Send the partitions
!        -------------------
         call SendPartitionsMPI( MeshFileType(self % mesh % meshFileName) == HOPRMESH )
!
!        Destruct the full mesh
!        ----------------------
         call self % mesh % Destruct()

      end if
!
!     **********************************************************
!     *              MESH CONSTRUCTION                         *
!     **********************************************************
!
      CALL constructMeshFromFile( self % mesh, self % mesh % meshFileName, CurrentNodes, Nx, Ny, Nz, MeshInnerCurves , dir2D, success )
!
!     Compute wall distances
!     ----------------------
#if defined(NAVIERSTOKES)
      call self % mesh % ComputeWallDistances
#endif
      IF(.NOT. success) RETURN
!
!     ----------------------------
!     Get the final number of DOFS
!     ----------------------------
!
      self % NDOF = 0
      DO k=1, self % mesh % no_of_elements
         associate(e => self % mesh % elements(k))
         self % NDOF = self % NDOF + (e % Nxyz(1) + 1) * (e % Nxyz(2) + 1) * (e % Nxyz(3) + 1)
         end associate
      END DO

!
!     ------------------------
!     Allocate and zero memory
!     ------------------------
!
      call self % mesh % AllocateStorage(self % NDOF, controlVariables,computeGradients)
!
!     ----------------------------------------------------
!     Get manufactured solution source term (if requested)
!     ----------------------------------------------------
!
#if defined(NAVIERSTOKES)
      IF (self % ManufacturedSol) THEN
         DO el = 1, SIZE(self % mesh % elements) 
            DO k=0, Nz(el)
               DO j=0, Ny(el)
                  DO i=0, Nx(el)
                     IF (flowIsNavierStokes) THEN
                        CALL ManufacturedSolutionSourceNS(self % mesh % elements(el) % geom % x(:,i,j,k), &
                                                          0._RP, &
                                                          self % mesh % elements(el) % storage % S_NS (:,i,j,k)  )
                     ELSE
                        CALL ManufacturedSolutionSourceEuler(self % mesh % elements(el) % geom % x(:,i,j,k), &
                                                             0._RP, &
                                                             self % mesh % elements(el) % storage % S_NS (:,i,j,k)  )
                     END IF
                  END DO
               END DO
            END DO
         END DO
      END IF
#endif
!
!     ------------------
!     Build the monitors
!     ------------------
!
      call self % monitors % construct (self % mesh, controlVariables)

#if defined(NAVIERSTOKES)
!
!     -------------------
!     Build the particles
!     -------------------
!

      self % particles % active = controlVariables % logicalValueForKey("lagrangian particles")
      if ( self % particles % active ) then 
            call self % particles % construct(self % mesh, controlVariables)
      endif 
#endif
      
      NULLIFY(Nx,Ny,Nz)
!
!     Stop measuring preprocessing time
!     ----------------------------------
      if (.not. self % mesh % child) call Stopwatch % Pause("Preprocessing")

      END SUBROUTINE ConstructDGSem

!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE DestructDGSem( self )
      IMPLICIT NONE 
      CLASS(DGSem) :: self
      INTEGER      :: k      !Counter
      
      CALL self % mesh % destruct
      
      call self % monitors % destruct
      
      END SUBROUTINE DestructDGSem
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE SaveSolutionForRestart( self, fUnit ) 
         IMPLICIT NONE
         CLASS(DGSem)     :: self
         INTEGER          :: fUnit
         INTEGER          :: k

         DO k = 1, SIZE(self % mesh % elements) 
            WRITE(fUnit) self % mesh % elements(k) % storage % Q
         END DO

      END SUBROUTINE SaveSolutionForRestart

      subroutine DGSEM_SetInitialCondition( self, controlVariables, initial_iteration, initial_time ) 
         use FTValueDictionaryClass
         USE mainKeywordsModule
         implicit none
         class(DGSEM)   :: self
         class(FTValueDictionary), intent(in)   :: controlVariables
         integer                                :: restartUnit
         integer,       intent(out)             :: initial_iteration
         real(kind=RP), intent(out)             :: initial_time 
!
!        ---------------
!        Local variables
!        ---------------
!
         character(len=LINE_LENGTH)             :: solutionName
         logical                                :: saveGradients
         procedure(UserDefinedInitialCondition_f) :: UserDefinedInitialCondition
         
         solutionName = controlVariables % stringValueForKey(solutionFileNameKey, requestedLength = LINE_LENGTH)
         solutionName = trim(getFileName(solutionName))
         
         IF ( controlVariables % logicalValueForKey(restartKey) )     THEN
            CALL self % mesh % LoadSolutionForRestart(controlVariables, initial_iteration, initial_time)
         ELSE
   
            call UserDefinedInitialCondition(self % mesh, FLUID_DATA_VARS)

            initial_time = 0.0_RP
            initial_iteration = 0
!
!           If solving incompressible NS + CahnHilliard, compatibilize density and phase field
!           ----------------------------------------------------------------------------------
#if defined(INCNS) && defined(CAHNHILLIARD)
            call self % mesh % ConvertPhaseFieldToDensity
#endif
!
!           Save the initial condition
!           --------------------------
            saveGradients = controlVariables % logicalValueForKey(saveGradientsToSolutionKey)
            write(solutionName,'(A,A,I10.10,A)') trim(solutionName), "_", initial_iteration, ".hsol"
            call self % mesh % SaveSolution(initial_iteration, initial_time, solutionName, saveGradients)

         END IF
         
         write(solutionName,'(A,A,I10.10)') trim(solutionName), "_", initial_iteration
         call self % mesh % Export( trim(solutionName) )
   
      end subroutine DGSEM_SetInitialCondition
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!     -----------------------------------------------------------------------------------
!     Specifies how to copy a DGSem object:
!     -> Trivial but must be defined since self % monitors have a user-defined assignment
!     -> Must be impure because of some pointers of the derived types
!     -----------------------------------------------------------------------------------
      impure elemental subroutine DGSEM_Assign (to, from)
         implicit none
         class(DGSem), intent(inout) :: to
         type (DGSem), intent(in)    :: from
         
         to % maxResidual        = from % maxResidual
         to % nodes              = from % nodes
         to % numberOfTimeSteps  = from % numberOfTimeSteps
         to % NDOF               = from % NDOF
         
         to % mesh               = from % mesh
         to % ManufacturedSol    = from % ManufacturedSol
         
         to % monitors  = from % monitors
         to % particles = from % particles
         
      end subroutine DGSEM_Assign
!
!////////////////////////////////////////////////////////////////////////
!
!  -----------------------------------
!  Compute maximum residual L_inf norm
!  -----------------------------------
!
   FUNCTION ComputeMaxResiduals(mesh) RESULT(maxResidual)
      use MPI_Process_Info
      IMPLICIT NONE
      CLASS(HexMesh), intent(in)  :: mesh
      REAL(KIND=RP) :: maxResidual(NTOTALVARS)
!
!     ---------------
!     Local variables
!     ---------------
!
      INTEGER       :: id , eq, ierr
      REAL(KIND=RP) :: localMaxResidual(NTOTALVARS)
      real(kind=RP) :: localR1, localR2, localR3, localR4, localR5, localc
      real(kind=RP) :: R1, R2, R3, R4, R5, c
      
      maxResidual = 0.0_RP
      R1 = 0.0_RP
      R2 = 0.0_RP
      R3 = 0.0_RP
      R4 = 0.0_RP
      R5 = 0.0_RP
      c    = 0.0_RP

!$omp parallel shared(maxResidual, R1, R2, R3, R4, R5, c, mesh) default(private)
!$omp do reduction(max:R1,R2,R3,R4,R5,c)
      DO id = 1, SIZE( mesh % elements )
#if defined(NAVIERSTOKES) || defined(INCNS)
         localR1 = maxval(abs(mesh % elements(id) % storage % QDot(1,:,:,:)))
         localR2 = maxval(abs(mesh % elements(id) % storage % QDot(2,:,:,:)))
         localR3 = maxval(abs(mesh % elements(id) % storage % QDot(3,:,:,:)))
         localR4 = maxval(abs(mesh % elements(id) % storage % QDot(4,:,:,:)))
         localR5 = maxval(abs(mesh % elements(id) % storage % QDot(5,:,:,:)))
#endif
#if defined(CAHNHILLIARD)
         localc    = maxval(abs(mesh % elements(id) % storage % cDot(:,:,:,:)))
#endif
      
#if defined(NAVIERSTOKES) || defined(INCNS)
         R1 = max(R1,localR1)
         R2 = max(R2,localR2)
         R3 = max(R3,localR3)
         R4 = max(R4,localR4)
         R5 = max(R5,localR5)
#endif
#if defined(CAHNHILLIARD)
         c    = max(c, localc)
#endif
      END DO
!$omp end do
!$omp end parallel

#if defined(NAVIERSTOKES) || defined(INCNS)
      maxResidual(1:NNS) = [R1, R2, R3, R4, R5]
#endif
      
#if defined(CAHNHILLIARD)
      maxResidual(NTOTALVARS) = c
#endif

#ifdef _HAS_MPI_
      if ( MPI_Process % doMPIAction ) then
         localMaxResidual = maxResidual
         call mpi_allreduce(localMaxResidual, maxResidual, NTOTALVARS, MPI_DOUBLE, MPI_MAX, &
                            MPI_COMM_WORLD, ierr)
      end if
#endif

   END FUNCTION ComputeMaxResiduals
!
!//////////////////////////////////////////////////////////////////////// 
!
!  -------------------------------------------------------------------
!  Estimate the maximum time-step of the system. This
!  routine computes a heuristic based on the smallest mesh
!  spacing (which goes as 1/N^2) AND the eigenvalues of the
!  particular hyperbolic system being solved (Euler or Navier Stokes). This is not
!  the only way to estimate the time-step, but it works in practice.
!  Other people use variations on this and we make no assertions that
!  it is the only or best way. Other variations look only at the smallest
!  mesh values, other account for differences across the element.
!     -------------------------------------------------------------------
   real(kind=RP) function MaxTimeStep( self, cfl, dcfl )
      use VariableConversion
      use MPI_Process_Info
      implicit none
      !------------------------------------------------
      type(DGSem)                :: self
      real(kind=RP), intent(in)  :: cfl      !<  Advective cfl number
      real(kind=RP), optional, intent(in)  :: dcfl     !<  Diffusive cfl number
#if defined(NAVIERSTOKES)
      !------------------------------------------------
      integer                       :: i, j, k, eID                     ! Coordinate and element counters
      integer                       :: N(3)                             ! Polynomial order in the three reference directions
      integer                       :: ierr                             ! Error for MPI calls
      real(kind=RP)                 :: eValues(3)                       ! Advective eigenvalues
      real(kind=RP)                 :: dcsi, deta, dzet                 ! Smallest mesh spacing
      real(kind=RP)                 :: dcsi2, deta2, dzet2              ! Smallest mesh spacing squared
      real(kind=RP)                 :: lamcsi_a, lamzet_a, lameta_a     ! Advective eigenvalues in the three reference directions
      real(kind=RP)                 :: lamcsi_v, lamzet_v, lameta_v     ! Diffusive eigenvalues in the three reference directions
      real(kind=RP)                 :: jac, mu, T                       ! Mapping Jacobian, viscosity and temperature
      real(kind=RP)                 :: Q(NCONS)                         ! The solution in a node
      real(kind=RP)                 :: TimeStep_Conv, TimeStep_Visc     ! Time-step for convective and diffusive terms
      real(kind=RP)                 :: localMax_dt_v, localMax_dt_a     ! Time step to perform MPI reduction
      type(NodalStorage_t), pointer :: spAxi_p, spAeta_p, spAzeta_p     ! Pointers to the nodal storage in every direction
      external                      :: ComputeEigenvaluesForState       ! Advective eigenvalues
      !--------------------------------------------------------
!     Initializations
!     ---------------
      
      TimeStep_Conv = huge(1._RP)
      TimeStep_Visc = huge(1._RP)
      
!$omp parallel shared(self,TimeStep_Conv,TimeStep_Visc,NodalStorage,cfl,dcfl,flowIsNavierStokes) default(private) 
!$omp do reduction(min:TimeStep_Conv,TimeStep_Visc)
      do eID = 1, SIZE(self % mesh % elements) 
         N = self % mesh % elements(eID) % Nxyz
         spAxi_p => NodalStorage(N(1))
         spAeta_p => NodalStorage(N(2))
         spAzeta_p => NodalStorage(N(3))
         
         if ( N(1) .ne. 0 ) then
            dcsi = 1.0_RP / abs( spAxi_p   % x(1) - spAxi_p   % x (0) )   

         else
            dcsi = 0.0_RP

         end if

         if ( N(2) .ne. 0 ) then
            deta = 1.0_RP / abs( spAeta_p  % x(1) - spAeta_p  % x (0) )
         
         else
            deta = 0.0_RP

         end if

         if ( N(3) .ne. 0 ) then
            dzet = 1.0_RP / abs( spAzeta_p % x(1) - spAzeta_p % x (0) )

         else
            dzet = 0.0_RP

         end if
         
         if (flowIsNavierStokes) then
            dcsi2 = dcsi*dcsi
            deta2 = deta*deta
            dzet2 = dzet*dzet
         end if
         
         do k = 0, N(3) ; do j = 0, N(2) ; do i = 0, N(1)
!
!           ------------------------------------------------------------
!           The maximum eigenvalues for a particular state is determined
!           by the physics.
!           ------------------------------------------------------------
!
            Q(1:NCONS) = self % mesh % elements(eID) % storage % Q(1:NCONS,i,j,k)
            CALL ComputeEigenvaluesForState( Q , eValues )
            
            jac      = self % mesh % elements(eID) % geom % jacobian(i,j,k)
!
!           ----------------------------
!           Compute contravariant values
!           ----------------------------
!              
            lamcsi_a =abs( self % mesh % elements(eID) % geom % jGradXi(IX,i,j,k)   * eValues(IX) + &
                           self % mesh % elements(eID) % geom % jGradXi(IY,i,j,k)   * eValues(IY) + &
                           self % mesh % elements(eID) % geom % jGradXi(IZ,i,j,k)   * eValues(IZ) ) * dcsi
  
            lameta_a =abs( self % mesh % elements(eID) % geom % jGradEta(IX,i,j,k)  * eValues(IX) + &
                           self % mesh % elements(eID) % geom % jGradEta(IY,i,j,k)  * eValues(IY) + &
                           self % mesh % elements(eID) % geom % jGradEta(IZ,i,j,k)  * eValues(IZ) ) * deta
  
            lamzet_a =abs( self % mesh % elements(eID) % geom % jGradZeta(IX,i,j,k) * eValues(IX) + &
                           self % mesh % elements(eID) % geom % jGradZeta(IY,i,j,k) * eValues(IY) + &
                           self % mesh % elements(eID) % geom % jGradZeta(IZ,i,j,k) * eValues(IZ) ) * dzet
            
            TimeStep_Conv = min( TimeStep_Conv, cfl*abs(jac)/(lamcsi_a+lameta_a+lamzet_a) )
            
            if (flowIsNavierStokes) then
               T        = Temperature(Q)
               mu       = SutherlandsLaw(T)
               lamcsi_v = mu * dcsi2 * abs(sum(self % mesh % elements(eID) % geom % jGradXi  (:,i,j,k)))
               lameta_v = mu * deta2 * abs(sum(self % mesh % elements(eID) % geom % jGradEta (:,i,j,k)))
               lamzet_v = mu * dzet2 * abs(sum(self % mesh % elements(eID) % geom % jGradZeta(:,i,j,k)))
               
               TimeStep_Visc = min( TimeStep_Visc, dcfl*abs(jac)/(lamcsi_v+lameta_v+lamzet_v) )
            end if
                  
         end do ; end do ; end do
      end do 
!$omp end do
!$omp end parallel
         
#ifdef _HAS_MPI_
      if ( MPI_Process % doMPIAction ) then
         localMax_dt_v = TimeStep_Visc
         localMax_dt_a = TimeStep_Conv
         call mpi_allreduce(localMax_dt_a, TimeStep_Conv, 1, MPI_DOUBLE, MPI_MIN, &
                            MPI_COMM_WORLD, ierr)
         call mpi_allreduce(localMax_dt_v, TimeStep_Visc, 1, MPI_DOUBLE, MPI_MIN, &
                            MPI_COMM_WORLD, ierr)
      end if
#endif
      
      if (TimeStep_Conv  < TimeStep_Visc) then
         self % mesh % dt_restriction = DT_CONV
         MaxTimeStep  = TimeStep_Conv
      else
         self % mesh % dt_restriction = DT_DIFF
         MaxTimeStep  = TimeStep_Visc
      end if
#endif
   end function MaxTimeStep
!
!////////////////////////////////////////////////////////////////////////
!
end module DGSEMClass
