!
!//////////////////////////////////////////////////////
!
!   @File:    ProblemFile.f90
!   @Author:  Juan Manzanero (juan.manzanero@upm.es)
!   @Created: Fri Jan 19 12:22:20 2018
!   @Last revision date: Tue Jan 23 16:27:55 2018
!   @Last revision author: Juan Manzanero (juan.manzanero@upm.es)
!   @Last revision commit: d97cdbe19b7a3be3cd0c8a1f01343de8c1714260
!
!//////////////////////////////////////////////////////
!
!
!////////////////////////////////////////////////////////////////////////
!
!      ProblemFile.f90
!      Created: June 26, 2015 at 8:47 AM 
!      By: David Kopriva  
!
!      The Problem File contains user defined procedures
!      that are used to "personalize" i.e. define a specific
!      problem to be solved. These procedures include initial conditions,
!      exact solutions (e.g. for tests), etc. and allow modifications 
!      without having to modify the main code.
!
!      The procedures, *even if empty* that must be defined are
!
!      UserDefinedSetUp
!      UserDefinedInitialCondition(mesh)
!      UserDefinedPeriodicOperation(mesh)
!      UserDefinedFinalize(mesh)
!      UserDefinedTermination
!
!//////////////////////////////////////////////////////////////////////// 
! 
         SUBROUTINE UserDefinedStartup
!
!        --------------------------------
!        Called before any other routines
!        --------------------------------
!
            IMPLICIT NONE  
         END SUBROUTINE UserDefinedStartup
!
!//////////////////////////////////////////////////////////////////////// 
! 
         SUBROUTINE UserDefinedFinalSetup(mesh , thermodynamics_, &
                                                 dimensionless_, &
                                                     refValues_ )
!
!           ----------------------------------------------------------------------
!           Called after the mesh is read in to allow mesh related initializations
!           or memory allocations.
!           ----------------------------------------------------------------------
!
            USE HexMeshClass
            use PhysicsStorage
            IMPLICIT NONE
            CLASS(HexMesh)                      :: mesh
            type(Thermodynamics_t), intent(in)  :: thermodynamics_
            type(Dimensionless_t),  intent(in)  :: dimensionless_
            type(RefValues_t),      intent(in)  :: refValues_
         END SUBROUTINE UserDefinedFinalSetup
!
!//////////////////////////////////////////////////////////////////////// 
! 
#if defined(NAVIERSTOKES)
         subroutine userdefinedinitialcondition(mesh, thermodynamics_, &
                                                      dimensionless_, &
                                                          refvalues_  )
!
!           ------------------------------------------------
!           called to set the initial condition for the flow
!              - by default it sets an uniform initial
!                 condition.
!           ------------------------------------------------
!
            use smconstants
            use physicsstorage
            use hexmeshclass
            implicit none
            class(hexmesh)                      :: mesh
            type(thermodynamics_t), intent(in)  :: thermodynamics_
            type(dimensionless_t),  intent(in)  :: dimensionless_
            type(refvalues_t),      intent(in)  :: refvalues_
!
!           ---------------
!           local variables
!           ---------------
!
            integer        :: eid, i, j, k
            real(kind=rp)  :: qq, u, v, w, p
            real(kind=rp)  :: q(n_eqn), phi, theta
            associate ( gammam2 => dimensionless_ % gammam2, &
                        gamma => thermodynamics_ % gamma )
            theta = refvalues_ % aoatheta*(pi/180.0_rp)
            phi   = refvalues_ % aoaphi*(pi/180.0_rp)
      
            do eid = 1, mesh % no_of_elements
               associate( nx => mesh % elements(eid) % nxyz(1), &
                          ny => mesh % elements(eid) % nxyz(2), &
                          nz => mesh % elements(eid) % nxyz(3) )
               do k = 0, nz;  do j = 0, ny;  do i = 0, nx 
                  qq = 1.0_rp
                  u  = qq*cos(theta)*cos(phi)
                  v  = qq*sin(theta)*cos(phi)
                  w  = qq*sin(phi)
      
                  q(1) = 1.0_rp
                  p    = 1.0_rp/(gammam2)
                  q(2) = q(1)*u
                  q(3) = q(1)*v
                  q(4) = q(1)*w
                  q(5) = p/(gamma - 1._rp) + 0.5_rp*q(1)*(u**2 + v**2 + w**2)

                  mesh % elements(eid) % storage % q(:,i,j,k) = q 
               end do;        end do;        end do
               end associate
            end do

            end associate
            
         end subroutine userdefinedinitialcondition
#elif defined(CAHNHILLIARD)
         subroutine userdefinedinitialcondition(mesh, thermodynamics_, &
                                                      dimensionless_, &
                                                          refvalues_  )
!
!           **************************************************************
!                 This function specifies the initial condition for a 
!              spinodal decomposition.
!           **************************************************************
!
            use smconstants
            use physicsstorage
            use hexmeshclass
            implicit none
            class(hexmesh)                      :: mesh
            type(thermodynamics_t), intent(in)  :: thermodynamics_
            type(dimensionless_t),  intent(in)  :: dimensionless_
            type(refvalues_t),      intent(in)  :: refvalues_
!
!           ---------------
!           Local variables
!           ---------------
!
            integer        :: eid, i, j, k
            real(kind=rp)  :: qq, u, v, w, p
            real(kind=rp)  :: q(n_eqn), phi, theta

            call random_seed()
      
            do eid = 1, mesh % no_of_elements
               associate( nx => mesh % elements(eid) % nxyz(1), &
                          ny => mesh % elements(eid) % nxyz(2), &
                          nz => mesh % elements(eid) % nxyz(3) )
               do k = 0, nz ; do j = 0, ny; do i = 0, nx 
                  call random_number(mesh % elements(eID) % storage % c(i,j,0))
                  mesh % elements(eID) % storage % c(i,j,k) = 2.0_RP * (mesh % elements(eID) % storage % c(i,j,k) - 0.5_RP)
               end do ; end do;        end do

               mesh % elements(eID) % storage % Q(1,:,:,:) = mesh % elements(eID) % storage % c
               end associate
            end do
            
         end subroutine userdefinedinitialcondition
#endif
         subroutine UserDefinedState1(x, t, nHat, Q, thermodynamics_, dimensionless_, refValues_)
!
!           -------------------------------------------------
!           Used to define an user defined boundary condition
!           -------------------------------------------------
!
            use SMConstants
            use PhysicsStorage
            implicit none
            real(kind=RP), intent(in)     :: x(NDIM)
            real(kind=RP), intent(in)     :: t
            real(kind=RP), intent(in)     :: nHat(NDIM)
            real(kind=RP), intent(inout)  :: Q(N_EQN)
            type(Thermodynamics_t),    intent(in)  :: thermodynamics_
            type(Dimensionless_t),     intent(in)  :: dimensionless_
            type(RefValues_t),         intent(in)  :: refValues_
         end subroutine UserDefinedState1

         subroutine UserDefinedNeumann(x, t, nHat, U_x, U_y, U_z)
!
!           --------------------------------------------------------
!           Used to define a Neumann user defined boundary condition
!           --------------------------------------------------------
!
            use SMConstants
            use PhysicsStorage
            implicit none
            real(kind=RP), intent(in)     :: x(NDIM)
            real(kind=RP), intent(in)     :: t
            real(kind=RP), intent(in)     :: nHat(NDIM)
            real(kind=RP), intent(inout)  :: U_x(N_GRAD_EQN)
            real(kind=RP), intent(inout)  :: U_y(N_GRAD_EQN)
            real(kind=RP), intent(inout)  :: U_z(N_GRAD_EQN)
         end subroutine UserDefinedNeumann

!
!//////////////////////////////////////////////////////////////////////// 
! 
         SUBROUTINE UserDefinedPeriodicOperation(mesh, time, Monitors)
!
!           ----------------------------------------------------------
!           Called at the output interval to allow periodic operations
!           to be performed
!           ----------------------------------------------------------
!
            USE HexMeshClass
#if defined(NAVIERSTOKES)
            use MonitorsClass
#endif
            IMPLICIT NONE
            CLASS(HexMesh)               :: mesh
            REAL(KIND=RP)                :: time
#if defined(NAVIERSTOKES)
            type(Monitor_t), intent(in) :: monitors
#else
            logical, intent(in) :: monitors
#endif
            
         END SUBROUTINE UserDefinedPeriodicOperation
!
!//////////////////////////////////////////////////////////////////////// 
! 
         subroutine UserDefinedSourceTerm(mesh, time, thermodynamics_, dimensionless_, refValues_)
!
!           --------------------------------------------
!           Called to apply source terms to the equation
!           --------------------------------------------
!
            USE HexMeshClass
            use PhysicsStorage
            IMPLICIT NONE
            CLASS(HexMesh)                        :: mesh
            REAL(KIND=RP)                         :: time
            type(Thermodynamics_t),    intent(in) :: thermodynamics_
            type(Dimensionless_t),     intent(in) :: dimensionless_
            type(RefValues_t),         intent(in) :: refValues_
!
!           ---------------
!           Local variables
!           ---------------
!
            integer  :: i, j, k, eID
!
!           Usage example (by default no source terms are added)
!           ----------------------------------------------------
!           do eID = 1, mesh % no_of_elements
!              associate ( e => mesh % elements(eID) )
!              do k = 0, e % Nxyz(3)   ; do j = 0, e % Nxyz(2) ; do i = 0, e % Nxyz(1)
!                 e % QDot(:,i,j,k) = e % QDot(:,i,j,k) + Source(:)
!              end do                  ; end do                ; end do
!           end do
   
         end subroutine UserDefinedSourceTerm
!
!//////////////////////////////////////////////////////////////////////// 
! 
         SUBROUTINE UserDefinedFinalize(mesh, time, iter, maxResidual, thermodynamics_, &
                                                    dimensionless_, &
                                                        refValues_, &  
                                                          monitors, &
                                                       elapsedTime, &
                                                           CPUTime   )
!
!           --------------------------------------------------------
!           Called after the solution computed to allow, for example
!           error tests to be performed
!           --------------------------------------------------------
!
            USE HexMeshClass
            use PhysicsStorage
#if defined(NAVIERSTOKES)
            use MonitorsClass
#endif
            IMPLICIT NONE
            CLASS(HexMesh)                        :: mesh
            REAL(KIND=RP)                         :: time
            integer                               :: iter
            real(kind=RP)                         :: maxResidual
            type(Thermodynamics_t),    intent(in) :: thermodynamics_
            type(Dimensionless_t),     intent(in) :: dimensionless_
            type(RefValues_t),         intent(in) :: refValues_
#if defined(NAVIERSTOKES)
            type(Monitor_t),          intent(in) :: monitors
#else
            logical, intent(in)  :: monitors
#endif
            real(kind=RP),             intent(in)  :: elapsedTime
            real(kind=RP),             intent(in)  :: CPUTime

         END SUBROUTINE UserDefinedFinalize
!
!//////////////////////////////////////////////////////////////////////// 
! 
      SUBROUTINE UserDefinedTermination
!
!        -----------------------------------------------
!        Called at the the end of the main driver after 
!        everything else is done.
!        -----------------------------------------------
!
         IMPLICIT NONE  
      END SUBROUTINE UserDefinedTermination
      