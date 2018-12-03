!
!////////////////////////////////////////////////////////////////////////
!
!      BDFTimeIntegrator.f90
!      Created: 2017-04-09 16:30:00 +0100 
!      By:  Andrés Rueda
!
!      Module for integrating in time using the Backward Differentiation Formulas (BDF)
!
!////////////////////////////////////////////////////////////////////////
MODULE BDFTimeIntegrator
   use SMConstants
   USE PhysicsStorage
   use HexMeshClass
   USE LinearSolverClass
   USE CSRMatrixClass
   USE FTValueDictionaryClass
   use TimeIntegratorDefinitions
   use MatrixClass
   use DGSEMClass
   use StorageClass              , only: SolutionStorage_t
   implicit none
   
   PRIVATE                          
   PUBLIC BDFIntegrator_t, TakeBDFStep, ComputeRHS, UpdateNewtonSol, BDF_SetPreviousSolution, bdf_order, BDF_MatrixShift, BDF_SetOrder
   
!
!  ********************
!  BDF integrator class
!  ********************
   type BDFIntegrator_t
      
      class(GenericLinSolver_t), allocatable :: linsolver     !  Linear solver
      integer                                :: StepsForJac   !· Maximum number of steps that should be taken for computing a new Jacobian matrix
      integer                                :: StepsSinceJac !  
      logical                                :: JacByConv     !· .TRUE. if the Jacobian must be computed only when the convergence is bad
      logical                                :: TimeAccurate  !· .TRUE. if this is a time-accurate simulation
      logical                                :: UserNewtonTol !· .TRUE. if the newton tolerance is specified by the user
      real(kind=RP)                          :: NewtonTol     !  Specified Newton tolerance
      
      contains
         procedure :: construct => ConstructBDFIntegrator
         procedure :: destruct  => DestructBDFIntegrator
         procedure :: TakeStep  => TakeBDFStep
   end type BDFIntegrator_t
   
!
!  Module variables
!  ----------------
   
   logical       :: computeA = .TRUE.  ! Compute Jacobian? (only valid if it is meant to be computed according to the convergence)
   logical       :: Adaptive_dt = .TRUE.
   integer       :: bdf_order       ! BDF order specified by user
   integer       :: order           ! BDF order to be used
   integer       :: StepsTaken = 0

!
!  BDF coefficients for constant time-step
!  ---------------------------------------
   real(kind=RP), parameter :: BDFCoeff(6,5) = &
!                    a_1             a_2     a_3           a_4             a_5          a_6
         reshape( (/ 1.0_RP        , -1._RP, 0._RP       , 0._RP         , 0._RP      , 0._RP        ,  &   ! BDF1
                     1.5_RP        , -2._RP, 0.5_RP      , 0._RP         , 0._RP      , 0._RP        ,  &   ! BDF2
                     11._RP/6_RP   , -3._RP, 3._RP/2._RP , -1._RP/3._RP  , 0._RP      , 0._RP        ,  &   ! BDF3
                     25._RP/12_RP  , -4._RP, 3._RP       , -4._RP/3._RP  , 1._RP/4._RP, 0._RP        ,  &   ! BDF4
                     137._RP/60_RP , -5._RP, 5._RP       , -10._RP/3._RP , 5._RP/4._RP, -1._RP/5._RP /) &   ! BDF5
                                                                                                      , (/6,5/) )
   integer, parameter :: MAX_ORDER_CONS_DT = 5
   
!
!  Default parameters for Newton iterative procedure
!  -------------------------------------------------
   real(kind=RP), parameter   :: NEWTON_MIN_CONVRATE = 0.1_RP     ! Minimum convergence rate for Newton method... If newton loop convergence rate passes this value, inner_dt is decreased
   real(kind=RP), parameter   :: NEWTON_MAX_CONVRATE = 1.7_RP     ! Maximum convergence rate for Newton method... If newton loop convergence rate passes this value, inner_dt is increased
   real(kind=RP), parameter   :: NEWTON_TOL_DEFAULT  = 1.e-6_RP   ! Default convergence tolerance
   integer      , parameter   :: MAX_NEWTON_ITER = 30          ! If newton iter reachs this limit, this iteration is marked as  not converged 
   integer      , parameter   :: LIM_NEWTON_ITER = 12          ! If Newton converges but this limit is reached, jacobian matrix will be recomputed
   logical                    :: PRINT_NEWTON_INFO
   
contains
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!  
   subroutine ConstructBDFIntegrator(this,controlVariables,sem)
      implicit none
      !--------------------------------------------------------
      class(BDFIntegrator_t) , intent(inout) :: this
      type(FTValueDictionary), intent(in)    :: controlVariables
      type(DGSem)            , intent(in)    :: sem
      !--------------------------------------------------------
      integer :: DimPrb
      !--------------------------------------------------------
      
!
!     Get general definitions
!     -----------------------

      Adaptive_dt = controlVariables % logicalValueForKey("implicit adaptive dt")
      this % JacByConv = controlVariables % LogicalValueForKey("jacobian by convergence")
      if (controlVariables % StringValueForKey("simulation type",LINE_LENGTH) == 'time-accurate') then
         this % TimeAccurate = .TRUE.
      else
         this % TimeAccurate = .FALSE.
      end if
      
      PRINT_NEWTON_INFO = controlVariables % logicalValueForKey("print newton info")
      if (controlVariables % containsKey("newton tolerance")) THEN
         this % UserNewtonTol = .TRUE.
         this % NewtonTol = controlVariables % doublePrecisionValueForKey("newton tolerance")
      else
         this % UserNewtonTol = .FALSE.
         this % NewtonTol = NEWTON_TOL_DEFAULT
      end if
      
      this % StepsForJac = controlVariables % integerValueForKey("compute jacobian every")
!
!     Setup linear solver
!     -------------------
      DimPrb = sem % NDOF * NTOTALVARS
      
      select case ( trim(controlVariables % StringValueForKey("linear solver",LINE_LENGTH)) )
         case('petsc')
            allocate (PetscKspLinearSolver_t :: this % linsolver)
         case('pardiso')
            allocate (MKLPardisoSolver_t     :: this % linsolver)
         case('matrix-free smooth')
            allocate (MatFreeSmooth_t        :: this % linsolver)
         case('matrix-free gmres')
            allocate (MatFreeGMRES_t         :: this % linsolver)
         case('smooth')
            allocate (IterativeSolver_t      :: this % linsolver)
         case('multigrid')
            allocate (MultigridSolver_t      :: this % linsolver)
         case('static-condensation')
            allocate (StaticCondSolver_t     :: this % linsolver)
         case default
            print*, "Keyword 'linear solver' missing... Using PETSc as default"
            allocate (PetscKspLinearSolver_t :: this % linsolver)
      end select
      
      call this % linsolver % construct (DimPrb,controlVariables,sem,BDF_MatrixShift)             !Constructs linear solver 
      
!
!     Setup BDF methods
!     -----------------
      call BDF_SetOrder( controlVariables % integerValueForKey("bdf order") )
      
      ! Check that the BDF order is consistent
      if (bdf_order > 1) then
         if ( (.not. controlVariables % containsKey("dt") ) .or. Adaptive_dt) then
            ERROR stop ':: "bdf order">1 is only valid with fixed time-step sizes'
         end if
      end if
      
   end subroutine ConstructBDFIntegrator
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!   
   subroutine DestructBDFIntegrator(this)
      implicit none
      !--------------------------------------------------------
      class(BDFIntegrator_t), intent(inout) :: this
      !--------------------------------------------------------
      
      call this % linsolver % destroy
      deallocate (this % linsolver)
      
   end subroutine DestructBDFIntegrator
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!   
   SUBROUTINE TakeBDFStep (this, sem, t , dt, ComputeTimeDerivative)
      implicit none
      !----------------------------------------------------------------------
      class(BDFIntegrator_t), intent(inout) :: this
      TYPE(DGSem),                  INTENT(inout)           :: sem                  !<>DGSem class with solution storage 
      REAL(KIND=RP),                INTENT(IN)              :: t                    !< Time at the beginning of time step
      REAL(KIND=RP),                INTENT(IN)              :: dt                   !< Initial (outer) time step (the subroutine can use a smaller one depending on convergence)
      procedure(ComputeTimeDerivative_f)                            :: ComputeTimeDerivative
      !----------------------------------------------------------------------
      
      real(kind=RP) :: time               ! Time at the beginning of each inner(!) time step
      INTEGER                                               :: k, newtonit
      
      REAL(KIND=RP)                                         :: ConvRate
      REAL(KIND=RP)                                         :: inner_dt
      LOGICAL                                               :: CONVERGED
      !----------------------------------------------------------------------
      
      IF ((.not. this % TimeAccurate) .and. (.not. this % UserNewtonTol)) THEN
         this % NewtonTol = sem % MaxResidual* 1e-3_RP
      END IF
      
      inner_dt = dt            ! first inner_dt is the outer step dt 
      time = t
      
      !**************************
      ! If the Jacobian must only be computed sometimes
       IF (this % JacByConv) THEN
         IF (.not. computeA) THEN
            CALL this % linsolver % ReSetOperatorDt(inner_dt)
         END IF
       ENDIF
      ! 
      !**************************
      
      call sem % mesh % storage % local2GlobalQ(sem % NDOF)
!
!     ********************
!     Sub-time-step solver
!     ********************
      do
         
!        Set previous solution for inner time-step
!        -----------------------------------------
         
         call BDF_SetPreviousSolution(sem % mesh % storage)
         
!        Perform Newton interative procedure
!        -----------------------------------
         
         if (computeA) then
            this % StepsSinceJac = 0
         else
            this % StepsSinceJac = this % StepsSinceJac + 1
            if (this % StepsSinceJac == this % StepsForJac) then
               computeA = .TRUE.
               this % StepsSinceJac = 0
            end if
         end if
         CALL NewtonSolve(sem, time+inner_dt, inner_dt, this % linsolver, this % NewtonTol, &
                          this % JacByConv,ConvRate, newtonit,CONVERGED, ComputeTimeDerivative)
         
!        Actions if Newton converged
!        ***************************
         IF (CONVERGED) THEN
            time = time + inner_dt
            
!           Check convergence to know if the Jacobian must be computed
!           ----------------------------------------------------------
            if (this % JacByConv .and. (newtonit > LIM_NEWTON_ITER) ) then   !Recomputes jacobian Matrix if convergence rate is poor
               if (PRINT_NEWTON_INFO) then
                  write(STD_OUT,*) "Convergence rate is poor, Jacobian matrix will be computed in next iteration..."
               end if
               computeA = .TRUE.                                        
            end if
            
!           Check if the sub time-stepping is done
!           --------------------------------------
            IF (ABS((time)-(t+dt)) < 10 * EPSILON(1._RP)) THEN       ! If outer t+dt is reached, the time integration is done
               EXIT                                            
            ENDIF
            
!           Increase dt if good convergence in previous step
!           ------------------------------------------------
            IF (Adaptive_dt .and. ConvRate > NEWTON_MAX_CONVRATE) THEN
               inner_dt = inner_dt * 2.0_RP
               IF (this % JacByConv)  CALL this % linsolver % ReSetOperatorDt(inner_dt)    ! Resets the operator with the new dt
               
               IF (PRINT_NEWTON_INFO) WRITE(*,*) "Increasing  dt  = ", inner_dt
            ENDIF
            
!           Adjust dt to prevent sub time-stepping to be be greater than outer Dt 
!           ---------------------------------------------------------------------
            IF ( time+inner_dt > t + dt) THEN  ! Adjusts inner dt to achieve exact outer Dt in the last substep
               inner_dt = t + dt - time
               IF (this % JacByConv)  CALL this % linsolver % ReSetOperatorDt(inner_dt)    ! Resets the operator with the new dt
               
               IF (PRINT_NEWTON_INFO) WRITE(*,*) "Adjusting dt = ", inner_dt
            ENDIF
         
!        Actions if Newton did not converge
!        **********************************
         ELSE
            
!           Reduce dt is allowed
!           --------------------
            if (Adaptive_dt) then
               inner_dt = inner_dt / 2._RP
               IF (this % JacByConv)  CALL this % linsolver % ReSetOperatorDt(inner_dt)    ! Resets the operator with the new dt
               
               sem % mesh % storage % Q = sem % mesh % storage % PrevQ(:, sem % mesh % storage % prevSol_index(1))  ! restores Q in sem to begin a new newton iteration
                 
               IF (PRINT_NEWTON_INFO) WRITE(*,*) "Newton loop did not converge, trying a smaller dt = ", inner_dt
               
!           Warn if dt cannot be changed
!           ----------------------------
            else
               if (this % TimeAccurate) then
                  ERROR stop 'Newton loop did not converge. Consider using a smaller dt or "implicit adaptive dt = .TRUE."'
               else
                  print*, 'WARNING: Newton loop did not converge. Consider using a smaller dt or "implicit adaptive dt = .TRUE."'
                  exit
               end if
            end if
         END IF
      
      END DO
 
      IF (PRINT_NEWTON_INFO) WRITE(*,'(A10,f5.2)') "ConvRate: ", ConvRate
      
      !**************************
      ! for computing sometimes
      IF (this % JacByConv .AND. ConvRate <0.65_RP ) THEN
         computeA = .TRUE.
      END IF
      ! for computing sometimes
      !**************************
      
!~       IF (MAXVAL(maxResidual) > sem % maxResidual) computeA = .TRUE.
      
      call sem % mesh % storage % global2LocalQ
      call sem % mesh % storage % global2LocalQdot
      
   END SUBROUTINE TakeBDFStep
!
!/////////////////////////////////////////////////////////////////////////////////////////////////
!
!  -------------------------------------------------------------
!  Routine for performing a nonlinear Newton iterative procedure
!  -> This can be taken out of the BDFTimeIntegrator if needed
!        (but careful with Adaptive_dt and the Newton vars)
!  -------------------------------------------------------------
   subroutine NewtonSolve(sem, t, dt, linsolver, NEWTON_TOLERANCE, JacByConv,ConvRate, niter,CONVERGED, ComputeTimeDerivative)
      implicit none
      !----------------------------------------------------------------------
      type(DGSem),                  intent(inout)           :: sem
      real(kind=RP),                intent(in)              :: t
      real(kind=RP),                intent(in)              :: dt              !< Inner dt
      class(GenericLinSolver_t),    intent(inout)           :: linsolver       !Linear operator is calculate outside this subroutine
      real(kind=RP),                intent(in)              :: NEWTON_TOLERANCE
      logical,                      intent(in)              :: JacByConv         !< Must the Jacobian be computed for bad convergence? if .false., the Jacobian is computed at the beginning of every newton it
      real(kind=RP),                intent(out)             :: ConvRate
      integer,                      intent(out)             :: niter
      logical,                      intent(out)             :: CONVERGED   
      procedure(ComputeTimeDerivative_f)                    :: ComputeTimeDerivative
      !----------------------------------------------------------------------
      integer(8)           :: cli, clf, clrate           
      integer              :: newtonit
      real(kind=RP)        :: norm, norm_old, rel_tol
      real(kind=RP)        :: linsolver_tol
      logical      , save  :: isfirst = .TRUE.
      real(kind=RP), save  :: norm1
      !----------------------------------------------------------------------
      
!
!     Initializations
!     ---------------
      
      IF (isfirst) THEN
         norm = 2.e-1_RP   ! A value to define the initial linsolver_tol
         isfirst = .FALSE.
      ELSE
         norm = norm1
      END IF
      norm_old = -1.0_RP  !Must be initialized to -1 to avoid bad things in the first newton iter
      ConvRate = 1.0_RP
   
      IF (PRINT_NEWTON_INFO) THEN
         WRITE(*, "(A9,1X,A18,1X,A18,1X,A15,1X,A12,1X,A18)") "Newton it", "Newton abs_err", "Newton rel_err", "LinSolverErr", "# ksp iter", "Iter wall time (s)"
      END IF
      
      CALL SYSTEM_CLOCK(COUNT_RATE=clrate)
!
!     Newton loop
!     -----------
      DO newtonit = 1, MAX_NEWTON_ITER
         if (.not. JacByConv) computeA = .TRUE.
         
         linsolver_tol = norm / ( 2._RP**(newtonit) )                      ! Nastase approach ("High-order discontinuous Galerkin methods using an hp-multigrid approach")
         
         CALL ComputeRHS(sem, t, dt, linsolver, ComputeTimeDerivative )               ! Computes b (RHS) and stores it into linsolver
         
         CALL SYSTEM_CLOCK(COUNT=cli)
         CALL linsolver%solve( nEqn=NTOTALVARS, nGradEqn=NTOTALGRADS, tol = linsolver_tol, maxiter=500, time= t, dt=dt, &
                              ComputeTimeDerivative = ComputeTimeDerivative, computeA = computeA)        ! Solve (J-I/dt)·x = (Q_r- U_n)/dt - Qdot_r
         CALL SYSTEM_CLOCK(COUNT=clf)
         IF (.NOT. linsolver%converged .and. Adaptive_dt) THEN                           ! If linsolver did not converge, return converged=false
            converged = .FALSE.
            RETURN
         ENDIF
         CALL UpdateNewtonSol(sem, linsolver)                    ! Q_r+1 = Q_r + x
         
         norm = linsolver%Getxnorm('infinity')

         IF (norm_old > 0._RP) THEN
            ConvRate = ConvRate + (LOG10(norm_old/norm)-ConvRate)/newtonit 
         ENDIF
         norm_old = norm
         niter = newtonit
         IF (newtonit == 1) THEN
            norm1 = norm
            rel_tol = norm1 * NEWTON_TOLERANCE
         ENDIF
         IF (PRINT_NEWTON_INFO) THEN
            WRITE(*, "(I9,1X,ES18.3,1X,ES18.3,1X,ES15.3,1X,I12,1X,F18.5)")newtonit, norm, norm/norm1, linsolver%Getrnorm(),&
                                                      linsolver%niter, (clf-cli)/real(clrate,RP)
         ENDIF
         
         IF (ConvRate < NEWTON_MIN_CONVRATE .OR. newtonit == MAX_NEWTON_ITER .OR. ISNAN(norm)) THEN
            IF (PRINT_NEWTON_INFO) print*, 'ConvRate: ', ConvRate
            converged = .FALSE.
            RETURN
         ENDIF
        
         IF (norm < max(rel_tol,NEWTON_TOLERANCE)) THEN ! Careful: this may not be appropriate for unsteady simulations
            converged = .TRUE. 
            RETURN
         ENDIF
         
      ENDDO
   
   END SUBROUTINE NewtonSolve
!  
!/////////////////////////////////////////////////////////////////////////////////////////////////
!
   SUBROUTINE ComputeRHS(sem, t, dt, linsolver, ComputeTimeDerivative )
      implicit none
      !----------------------------------------------------------------
      TYPE(DGSem),                intent(inout)    :: sem
      REAL(KIND=RP),              intent(IN)       :: t
      REAL(KIND=RP),              intent(IN)       :: dt
      CLASS(GenericLinSolver_t),  intent (inout)   :: linsolver
      procedure(ComputeTimeDerivative_f)                   :: ComputeTimeDerivative
      !----------------------------------------------------------------
      INTEGER                                      :: Nx, Ny, Nz, l, i, j, k, elmnt, counter   
      REAL(KIND=RP)                                :: value
      real(kind=RP)  :: RHS(NTOTALVARS*sem % NDOF)
      !----------------------------------------------------------------
      
      call sem % mesh % storage % global2LocalQ
      call ComputeTimeDerivative( sem % mesh, sem % particles, t, CTD_IGNORE_MODE)
      call sem % mesh % storage % local2GlobalQdot(sem % NDOF)
      
      RHS = BDF_GetRHS(sem % mesh % storage, dt)
      
      do i=1, sem % NDOF * NTOTALVARS                                ! TODO: Use SetRHS!!
         CALL linsolver % SetRHSValue(i-1, RHS(i))
      end do
      
      CALL linsolver % AssemblyRHS     ! b must be assembled before using
   END SUBROUTINE ComputeRHS
!  
!/////////////////////////////////////////////////////////////////////////////////////////////////
!  
   SUBROUTINE UpdateNewtonSol(sem, linsolver)

      TYPE(DGSem),                     intent(inout)    :: sem
      CLASS(GenericLinSolver_t),       intent(inout)    :: linsolver
      
      sem % mesh % storage % Q = sem % mesh % storage % Q  + linsolver % GetX()
      
   END SUBROUTINE UpdateNewtonSol
!
!////////////////////////////////////////////////////////////////////////////////////////////
!  TODO: Move from here....
   SUBROUTINE WriteEigenFiles(Mat,sem,FileName)
      IMPLICIT NONE
!
!     -----------------------------------------------------------
!     Writes files for performing eigenvalue analysis using TAUev
!        This only works for isotropic order meshes.........................TODO: Change that
!     -----------------------------------------------------------
!
      TYPE(csrMat_t)    :: Mat      !< Jacobian matrix
      TYPE(DGSem)       :: sem      !< DGSem class containing mesh
      CHARACTER(len=*)  :: FileName !< ...
!     -----------------------------------------------------------
      INTEGER           :: fd
!     -----------------------------------------------------------
      
      ! .frm file
      OPEN(newunit=fd, file=TRIM(FileName)//'.frm', action='WRITE')
         WRITE(fd,*)
         WRITE(fd,*) SIZE(Mat % Values), SIZE(Mat % Rows)-1, 1, NTOTALVARS, 1
         WRITE(fd,*) sem % mesh % elements(1) % Nxyz(1), SIZE(sem % mesh % elements)
      CLOSE (fd)
      
      ! .amg file
      CALL Mat % Visualize(TRIM(FileName)//'.amg',FirstRow=.FALSE.)
      
      ! .coo file
      CALL sem % mesh % WriteCoordFile(NTOTALVARS, TRIM(FileName)//'.coo')
      
      
   END SUBROUTINE WriteEigenFiles
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   subroutine BDF_SetOrder(order)
      implicit none
      !------------------------------------------------------
      integer, intent(in) :: order
      !------------------------------------------------------
      
      if (order > MAX_ORDER_CONS_DT) then
         write(STD_OUT,*) 'WARNING :: Maximum BDF order for constant time-step is 5. Using 1 by default.'
         bdf_order = 1
      else
         bdf_order = order
      end if
      
   end subroutine BDF_SetOrder
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   subroutine BDF_SetPreviousSolution(storage,NotANewStep)
      implicit none
      !------------------------------------------------------
      type(SolutionStorage_t), intent(inout) :: storage
      logical, optional :: NotANewStep
      !------------------------------------------------------
      integer :: i      ! Counter
      !------------------------------------------------------
      
      if (present(NotANewStep)) then
         if (.not. NotANewStep) StepsTaken = StepsTaken + 1
      else
         StepsTaken = StepsTaken + 1
      end if
      
      order = min(StepsTaken, bdf_order)
      
      call storage % SetGlobalPrevQ(storage % Q)
   end subroutine BDF_SetPreviousSolution
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   function BDF_MatrixShift(dt) result(Ashift)
      implicit none
      !------------------------------------------------------
      real(kind=RP), intent(in) :: dt
      real(kind=RP)             :: Ashift
      !------------------------------------------------------
      
      Ashift = -BDFCoeff(1,order)/dt
      
   end function BDF_MatrixShift
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   function BDF_GetRHS(storage,dt) result(RHS)
      implicit none
      !------------------------------------------------------
      type(SolutionStorage_t), intent(in) :: storage
      real(kind=RP)          , intent(in) :: dt
      real(kind=RP)                       :: RHS(size(storage % Q))
      !------------------------------------------------------
      integer :: k
      real(kind=RP) :: invdt
      !------------------------------------------------------
      
      invdt = 1._RP/dt
      
      RHS = storage % Q * BDFCoeff(1,order)*invdt - storage % Qdot
      
      do k=1, order
         RHS = RHS + BDFCoeff(k+1,order) * storage % PrevQ(:,storage % prevSol_index(k)) * invdt
      end do
      
   end function BDF_GetRHS
   
!~   subroutine BDFCoefficientsVariable_dt(order,dt)
!~      implicit none
!~      integer      , intent(in) :: order
!~      real(kind=RP), intent(in) :: dt(order)
      
!~      select case(order)
!~         case (1)
!~            a(1) = 1.0_RP / dt(1)
!~            a(2) = -1.0_RP / dt(1)
!~         case (2)
!~            a(1) = a(1) + 1.0_RP / (dt(1)+dt(2)) 
!~            a(2) = a(2) - (1.0_RP + dt(1)/dt(2)) / (dt(1)+dt(2)) 
!~            a(3) = (dt(1)/dt(2)) / (dt(1)+dt(2)) 
!~         case (3)
!~            a(1) = a(1) + 1.0_RP / (dt(1)+dt(2)+dt(3)) 
!~            a(2) = a(2) - (1.0_RP + dt(1)/dt(2)*(1.0+(dt(1)+dt(2))/(dt(2)+dt(3)))) / (dt(1)+dt(2)+dt(3)) 
!~            a(3) = a(3) + (dt(1)/dt(2)*(1.0+(dt(1)+dt(2))/(dt(2)+dt(3))) + &
!~                     dt(1)/dt(3)*(dt(1)+dt(2))/(dt(2)+dt(3)) ) / (dt(1)+dt(2)+dt(3)) 
!~            a(4) = -(dt(1)/dt(3))*(dt(1)+dt(2))/(dt(2)+dt(3)) / (dt(1)+dt(2)+dt(3))
!~         case default
!~            ERROR stop ':: variable time-step BDF only up to order 3'
!~      end select
!~   end subroutine
END MODULE BDFTimeIntegrator
