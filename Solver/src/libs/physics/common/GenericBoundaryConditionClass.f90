!
!//////////////////////////////////////////////////////
!
!   @File:    GenericBoundaryConditionClass.f90
!   @Author:  Juan Manzanero (juan.manzanero@upm.es)
!   @Created: Wed Jul 25 15:26:42 2018
!   @Last revision date:
!   @Last revision author:
!   @Last revision commit:
!
!//////////////////////////////////////////////////////
!
#include "Includes.h"
module GenericBoundaryConditionClass
   use SMConstants
   use PhysicsStorage
   use FTValueDictionaryClass, only: FTValueDictionary
   implicit none
!
!  *****************************
!  Default everything to private
!  *****************************
!
   private
!
!  ****************
!  Public variables
!  ****************
!
   public NS_BC, C_BC, MU_BC
!
!  ******************
!  Public definitions
!  ******************
!
   public GenericBC_t, GetValueWithDefault
!
!  ****************************
!  Static variables definitions
!  ****************************
!
   enum, bind(C)
      enumerator :: NONE_BC
      enumerator :: NS_BC
      enumerator :: C_BC, MU_BC
   end enum
!
!  ****************
!  Class definition
!  ****************
!
   type GenericBC_t
      logical                    :: constructed = .false.
      character(len=LINE_LENGTH) :: bname
      character(len=LINE_LENGTH) :: BCType
      integer                    :: currentEqn
      contains
         procedure         :: Destruct          => GenericBC_Destruct
         procedure         :: Describe          => GenericBC_Describe
#if defined(NAVIERSTOKES) || defined(INCNS)
         procedure         :: FlowState         => GenericBC_FlowState
         procedure         :: FlowNeumann       => GenericBC_FlowNeumann
#endif
#if defined(CAHNHILLIARD)
         procedure         :: PhaseFieldState   => GenericBC_PhaseFieldState
         procedure         :: PhaseFieldNeumann => GenericBC_PhaseFieldNeumann
         procedure         :: ChemPotState      => GenericBC_ChemPotState
         procedure         :: ChemPotNeumann    => GenericBC_ChemPotNeumann
#endif
         procedure         :: StateForEqn
         procedure         :: NeumannForEqn
   end type GenericBC_t
!
!  *******************************************************************
!  Traditionally, constructors are exported with the name of the class
!  *******************************************************************
!
   interface GenericBC_t
      module procedure ConstructGenericBC
   end interface GenericBC_t
!
!  *******************
!  Function prototypes
!  *******************
!
   abstract interface
   end interface
!
!  ========
   contains
!  ========
!
!/////////////////////////////////////////////////////////
!
!        Class constructor
!        -----------------
!
!/////////////////////////////////////////////////////////
!
      function ConstructGenericBC()
!
!        ************************************************************
!        This is a default constructor (i.e. without input arguments)
!        ************************************************************
!
         implicit none
         type(GenericBC_t)  :: ConstructGenericBC
   
         print*, "Default Boundary condition class can not be constructed."
         errorMessage(STD_OUT)
         stop

      end function ConstructGenericBC
!
!/////////////////////////////////////////////////////////
!
!        Class destructors
!        -----------------
!
!/////////////////////////////////////////////////////////
!
      subroutine GenericBC_Destruct(self)
         implicit none
         class(GenericBC_t)    :: self

         if (.not. self % constructed) return
      
      end subroutine GenericBC_Destruct
!
!//////////////////////////////////////////////////////////////////////////////////
!
!        This subroutine allows to call the State/Neumann for generic equations
!        ----------------------------------------------------------------------
!
!//////////////////////////////////////////////////////////////////////////////////
!
      subroutine StateForEqn(self, nEqn, x, t, nHat, Q)
         implicit none
         class(GenericBC_t),  intent(in)    :: self
         integer,             intent(in)    :: nEqn
         real(kind=RP),       intent(in)    :: x(NDIM)
         real(kind=RP),       intent(in)    :: t
         real(kind=RP),       intent(in)    :: nHat(NDIM)
         real(kind=RP),       intent(inout) :: Q(nEqn)

#if (!defined(CAHNHILLIARD))
         call self % FlowState(x, t, nHat, Q)

#else
         select case(self % currentEqn)
#if defined(NAVIERSTOKES) || defined(INCNS)
         case(NS_BC)
            call self % FlowState(x, t, nHat, Q)
#endif
         case(C_BC)
            call self % PhaseFieldState(x, t, nHat, Q)
   
         case(MU_BC)
            call self % ChemPotState(x, t, nHat, Q)

         end select
#endif

      end subroutine StateForEqn

      subroutine NeumannForEqn(self, which, nEqn, nGradEqn, x, t, nHat, Q, U_x, U_y, U_z)
         implicit none
         class(GenericBC_t),  intent(in)    :: self
         integer,             intent(in)    :: which
         integer,             intent(in)    :: nEqn
         integer,             intent(in)    :: nGradEqn
         real(kind=RP),       intent(in)    :: x(NDIM)
         real(kind=RP),       intent(in)    :: t
         real(kind=RP),       intent(in)    :: nHat(NDIM)
         real(kind=RP),       intent(inout) :: Q(nEqn)
         real(kind=RP),       intent(inout) :: U_x(nGradEqn)
         real(kind=RP),       intent(inout) :: U_y(nGradEqn)
         real(kind=RP),       intent(inout) :: U_z(nGradEqn)


#if (!defined(CAHNHILLIARD))
         call self % FlowNeumann(x, t, nHat, Q, U_x, U_y, U_z)

#else
         select case(self % currentEqn)
#if defined(NAVIERSTOKES) || defined(INCNS)
         case(NS_BC)
            call self % FlowNeumann(x, t, nHat, Q, U_x, U_y, U_z)
#endif
         case(C_BC)
            call self % PhaseFieldNeumann(x, t, nHat, Q, U_x, U_y, U_z)
   
         case(MU_BC)
            call self % ChemPotNeumann(x, t, nHat, Q, U_x, U_y, U_z)

         end select
#endif

      end subroutine NeumannForEqn
!
!////////////////////////////////////////////////////////////////////////////
!
!        Subroutines for compressible Navier--Stokes equations
!        -----------------------------------------------------
!
!////////////////////////////////////////////////////////////////////////////
!
#if defined(NAVIERSTOKES)
      subroutine GenericBC_FlowState(self, x, t, nHat, Q)
         implicit none
         class(GenericBC_t),  intent(in)    :: self
         real(kind=RP),       intent(in)    :: x(NDIM)
         real(kind=RP),       intent(in)    :: t
         real(kind=RP),       intent(in)    :: nHat(NDIM)
         real(kind=RP),       intent(inout) :: Q(NCONS)
      end subroutine GenericBC_FlowState

      subroutine GenericBC_FlowNeumann(self, x, t, nHat, Q, U_x, U_y, U_z)
         implicit none
         class(GenericBC_t),  intent(in)    :: self
         real(kind=RP),       intent(in)    :: x(NDIM)
         real(kind=RP),       intent(in)    :: t
         real(kind=RP),       intent(in)    :: nHat(NDIM)
         real(kind=RP),       intent(inout) :: Q(NCONS)
         real(kind=RP),       intent(inout) :: U_x(NGRAD)
         real(kind=RP),       intent(inout) :: U_y(NGRAD)
         real(kind=RP),       intent(inout) :: U_z(NGRAD)
      end subroutine GenericBC_FlowNeumann
#endif
!
!////////////////////////////////////////////////////////////////////////////
!
!        Subroutines for incompressible Navier--Stokes equations
!        -------------------------------------------------------
!
!////////////////////////////////////////////////////////////////////////////
!
#if defined(INCNS)
      subroutine GenericBC_FlowState(self, x, t, nHat, Q)
         implicit none
         class(GenericBC_t),  intent(in)    :: self
         real(kind=RP),       intent(in)    :: x(NDIM)
         real(kind=RP),       intent(in)    :: t
         real(kind=RP),       intent(in)    :: nHat(NDIM)
         real(kind=RP),       intent(inout) :: Q(NINC)
      end subroutine GenericBC_FlowState

      subroutine GenericBC_FlowNeumann(self, x, t, nHat, Q, U_x, U_y, U_z)
         implicit none
         class(GenericBC_t),  intent(in)    :: self
         real(kind=RP),       intent(in)    :: x(NDIM)
         real(kind=RP),       intent(in)    :: t
         real(kind=RP),       intent(in)    :: nHat(NDIM)
         real(kind=RP),       intent(inout) :: Q(NINC)
         real(kind=RP),       intent(inout) :: U_x(NINC)
         real(kind=RP),       intent(inout) :: U_y(NINC)
         real(kind=RP),       intent(inout) :: U_z(NINC)
      end subroutine GenericBC_FlowNeumann
#endif
!
!////////////////////////////////////////////////////////////////////////////
!
!        Subroutines for Cahn--Hilliard
!        ------------------------------
!
!////////////////////////////////////////////////////////////////////////////
!
#if defined(CAHNHILLIARD)
      subroutine GenericBC_PhaseFieldState(self, x, t, nHat, Q)
         implicit none
         class(GenericBC_t),  intent(in)    :: self
         real(kind=RP),       intent(in)    :: x(NDIM)
         real(kind=RP),       intent(in)    :: t
         real(kind=RP),       intent(in)    :: nHat(NDIM)
         real(kind=RP),       intent(inout) :: Q(NCOMP)
      end subroutine GenericBC_PhaseFieldState

      subroutine GenericBC_PhaseFieldNeumann(self, x, t, nHat, Q, U_x, U_y, U_z)
         implicit none
         class(GenericBC_t),  intent(in)    :: self
         real(kind=RP),       intent(in)    :: x(NDIM)
         real(kind=RP),       intent(in)    :: t
         real(kind=RP),       intent(in)    :: nHat(NDIM)
         real(kind=RP),       intent(inout) :: Q(NCOMP)
         real(kind=RP),       intent(inout) :: U_x(NCOMP)
         real(kind=RP),       intent(inout) :: U_y(NCOMP)
         real(kind=RP),       intent(inout) :: U_z(NCOMP)
      end subroutine GenericBC_PhaseFieldNeumann

      subroutine GenericBC_ChemPotState(self, x, t, nHat, Q)
         implicit none
         class(GenericBC_t),  intent(in)    :: self
         real(kind=RP),       intent(in)    :: x(NDIM)
         real(kind=RP),       intent(in)    :: t
         real(kind=RP),       intent(in)    :: nHat(NDIM)
         real(kind=RP),       intent(inout) :: Q(NCOMP)
      end subroutine GenericBC_ChemPotState

      subroutine GenericBC_ChemPotNeumann(self, x, t, nHat, Q, U_x, U_y, U_z)
         implicit none
         class(GenericBC_t),  intent(in)    :: self
         real(kind=RP),       intent(in)    :: x(NDIM)
         real(kind=RP),       intent(in)    :: t
         real(kind=RP),       intent(in)    :: nHat(NDIM)
         real(kind=RP),       intent(inout) :: Q(NCOMP)
         real(kind=RP),       intent(inout) :: U_x(NCOMP)
         real(kind=RP),       intent(inout) :: U_y(NCOMP)
         real(kind=RP),       intent(inout) :: U_z(NCOMP)
      end subroutine GenericBC_ChemPotNeumann
#endif

      subroutine GenericBC_Describe(self)
         implicit none
         class(GenericBC_t),  intent(in)  :: self
      end subroutine GenericBC_Describe
!
!////////////////////////////////////////////////////////////////////////////
!
!        Some utilities
!        --------------
!
!////////////////////////////////////////////////////////////////////////////
!
      subroutine GetValueWithDefault(controlVariables, keyword, default, val)
         implicit none
         type(FTValueDictionary),    intent(in)  :: controlVariables
         character(len=*),           intent(in)  :: keyword
         real(kind=RP),              intent(in)  :: default
         real(kind=RP),              intent(out) :: val
!
!        ---------------
!        Local variables
!        ---------------
!
         if ( controlVariables % ContainsKey(trim(keyword)) ) then
            val = controlVariables % DoublePrecisionValueForKey(trim(keyword))
         else
            val = default
         end if
   
      end subroutine GetValueWithDefault

end module GenericBoundaryConditionClass
