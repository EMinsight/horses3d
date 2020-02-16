!
!//////////////////////////////////////////////////////
!
!   @File:    Physics_NS.f90
!   @Author:  David Kopriva
!   @Created: Tue Jul 20 18:27:46 2011
!   @Last revision date: Mon Apr 22 18:37:36 2019
!   @Last revision author: Andrés Rueda (am.rueda@upm.es)
!   @Last revision commit: 8515114b0e5db8a89971614296ae2dd81ba0f8ee
!
!//////////////////////////////////////////////////////
!
!      Compressible Navier-Stokes physics.
!      Modified from DSEM Code
!
!!     The variable mappings for the Navier-Stokes Equations are
!!
!!              Q(1) = rho
!!              Q(2) = rhou
!!              Q(3) = rhov
!!              Q(4) = rhow
!!              Q(5) = rhoe
!
!////////////////////////////////////////////////////////////////////////
!    
!@mark -
!
#include "Includes.h"
!  **************
   module Physics_NS
!  **************
!
      use SMConstants
      use PhysicsStorage_NS
      use VariableConversion_NS
      use FluidData_NS
      use Utilities, only: outer_product
      implicit none

      private
      public  EulerFlux
      public  ViscousFlux0D_STATE, ViscousFlux2D_STATE, ViscousFlux3D_STATE
      public  ViscousFlux0D_withSGS, ViscousFlux2D_withSGS, ViscousFlux3D_withSGS
      public  EulerFlux0D, EulerFlux3D
      public  InviscidJacobian
      public  getStressTensor, SutherlandsLaw, ViscousJacobian

     interface EulerFlux
         module procedure EulerFlux0D, EulerFlux3D
     end interface EulerFlux
!
!     ========
      CONTAINS 
!     ========
!
!     
!
!//////////////////////////////////////////////////////////////////////////////
!
!           INVISCID FLUXES
!           ---------------   
!
!//////////////////////////////////////////////////////////////////////////////
!
      pure subroutine EulerFlux0D(Q, F, rho_)
         implicit none
         real(kind=RP), intent(in)   :: Q(1:NCONS)
         real(kind=RP), intent(out)  :: F(1:NCONS , 1:NDIM)
         real(kind=RP), intent(in), optional :: rho_
!
!        ---------------
!        Local variables
!        ---------------
!
         real(kind=RP)           :: u , v , w , p

         associate ( gammaMinus1 => thermodynamics % gammaMinus1 ) 

         u = Q(IRHOU) / Q(IRHO)
         v = Q(IRHOV) / Q(IRHO)
         w = Q(IRHOW) / Q(IRHO)
         p = gammaMinus1 * (Q(IRHOE) - 0.5_RP * ( Q(IRHOU) * u + Q(IRHOV) * v + Q(IRHOW) * w ) )
!
!        X-Flux
!        ------         
         F(IRHO , IX ) = Q(IRHOU)
         F(IRHOU, IX ) = Q(IRHOU) * u + p
         F(IRHOV, IX ) = Q(IRHOU) * v
         F(IRHOW, IX ) = Q(IRHOU) * w
         F(IRHOE, IX ) = ( Q(IRHOE) + p ) * u
!
!        Y-Flux
!        ------
         F(IRHO , IY ) = Q(IRHOV)
         F(IRHOU ,IY ) = F(IRHOV,IX)
         F(IRHOV ,IY ) = Q(IRHOV) * v + p
         F(IRHOW ,IY ) = Q(IRHOV) * w
         F(IRHOE ,IY ) = ( Q(IRHOE) + p ) * v
!
!        Z-Flux
!        ------
         F(IRHO ,IZ) = Q(IRHOW)
         F(IRHOU,IZ) = F(IRHOW,IX)
         F(IRHOV,IZ) = F(IRHOW,IY)
         F(IRHOW,IZ) = Q(IRHOW) * w + P
         F(IRHOE,IZ) = ( Q(IRHOE) + p ) * w
      
         end associate

      end subroutine EulerFlux0D

      pure subroutine EulerFlux3D(N, Q, F, rho_)
         implicit none
         integer,       intent(in)  :: N(3)
         real(kind=RP), intent(in)  :: Q(1:NCONS,0:N(1),0:N(2),0:N(3))
         real(kind=RP), intent(out) :: F(1:NCONS,0:N(1),0:N(2),0:N(3),1:NDIM)
         real(kind=RP), intent(in), optional :: rho_(0:N(1), 0:N(2), 0:N(3))
!
!        ---------------
!        Local variables
!        ---------------
!
         integer                 :: i, j, k
         real(kind=RP)           :: u(0:N(1),0:N(2),0:N(3)) , v(0:N(1),0:N(2),0:N(3)) , w(0:N(1),0:N(2),0:N(3)) , p(0:N(1),0:N(2),0:N(3))

         associate ( gammaMinus1 => thermodynamics % gammaMinus1 ) 

         do k = 0, N(3) ; do j = 0, N(2) ; do i = 0, N(1)
            u(i,j,k) = Q(IRHOU,i,j,k) / Q(IRHO,i,j,k)
            v(i,j,k) = Q(IRHOV,i,j,k) / Q(IRHO,i,j,k)
            w(i,j,k) = Q(IRHOW,i,j,k) / Q(IRHO,i,j,k)
            p(i,j,k) = gammaMinus1 * (Q(IRHOE,i,j,k) - 0.5_RP * ( Q(IRHOU,i,j,k) * u(i,j,k) + Q(IRHOV,i,j,k) * v(i,j,k) + Q(IRHOW,i,j,k) * w(i,j,k) ) )
            
            F(IRHO,i,j,k , IX ) = Q(IRHOU,i,j,k)
            F(IRHOU,i,j,k, IX ) = Q(IRHOU,i,j,k) * u(i,j,k) + p(i,j,k)
            F(IRHOV,i,j,k, IX ) = Q(IRHOU,i,j,k) * v(i,j,k)
            F(IRHOW,i,j,k, IX ) = Q(IRHOU,i,j,k) * w(i,j,k)
            F(IRHOE,i,j,k, IX ) = ( Q(IRHOE,i,j,k) + p(i,j,k) ) * u(i,j,k)

         end do   ; end do          ; end do
   
         do k = 0, N(3) ; do j = 0, N(2) ; do i = 0, N(1)
            F(IRHO,i,j,k , IY ) = Q(IRHOV,i,j,k)
            F(IRHOU,i,j,k ,IY ) = Q(IRHOU,i,j,k) * v(i,j,k)
            F(IRHOV,i,j,k ,IY ) = Q(IRHOV,i,j,k) * v(i,j,k) + p(i,j,k)
            F(IRHOW,i,j,k ,IY ) = Q(IRHOV,i,j,k) * w(i,j,k)
            F(IRHOE,i,j,k ,IY ) = ( Q(IRHOE,i,j,k) + p(i,j,k) ) * v(i,j,k)
         end do   ; end do          ; end do
   
         do k = 0, N(3) ; do j = 0, N(2) ; do i = 0, N(1)
            F(IRHO,i,j,k ,IZ) = Q(IRHOW,i,j,k)
            F(IRHOU,i,j,k,IZ) = Q(IRHOW,i,j,k) * u(i,j,k)
            F(IRHOV,i,j,k,IZ) = Q(IRHOW,i,j,k) * v(i,j,k)
            F(IRHOW,i,j,k,IZ) = Q(IRHOW,i,j,k) * w(i,j,k) + p(i,j,k)
            F(IRHOE,i,j,k,IZ) = ( Q(IRHOE,i,j,k) + p(i,j,k) ) * w(i,j,k)
         end do   ; end do          ; end do

         end associate

      end subroutine EulerFlux3D
!
!     -------------------------------------------------------------------------------
!     Subroutine for computing the Jacobian of the inviscid flux when it has the form 
!
!        F = f*iHat + g*jHat + h*kHat
!
!     First index indicates the flux term and second index indicates the conserved 
!     variable term. For example:
!           dfdq     := df/dq
!                       d f(2) |
!           dfdq(2,4) = ------ |
!                       d q(4) |q
!     ***** This routine is necessary for computing the analytical Jacobian. *****
!     -------------------------------------------------------------------------------
      pure subroutine InviscidJacobian(q,dfdq,dgdq,dhdq)
         implicit none
         !-------------------------------------------------
         real(kind=RP), intent (in)  :: q(NCONS)
         real(kind=RP), intent (out) :: dfdq(NCONS,NCONS)
         real(kind=RP), intent (out) :: dgdq(NCONS,NCONS)
         real(kind=RP), intent (out) :: dhdq(NCONS,NCONS)
         !-------------------------------------------------
         real(kind=RP)  :: u,v,w ! Velocity components
         real(kind=RP)  :: V2    ! Total velocity squared
         real(kind=RP)  :: p     ! Pressure
         real(kind=RP)  :: H     ! Total enthalpy
         !-------------------------------------------------
         
         associate( gammaMinus1 => thermodynamics % gammaMinus1, & 
                    gamma => thermodynamics % gamma )
         
         u  = q(IRHOU) / q(IRHO)
         v  = q(IRHOV) / q(IRHO)
         w  = q(IRHOW) / q(IRHO)
         V2 = u*u + v*v + w*w
         p  = Pressure(q)
         H  = (q(IRHOE) + p) / q(IRHO)
!
!        Flux in the x direction (f)
!        ---------------------------

         dfdq(1,1) = 0._RP
         dfdq(1,2) = 1._RP
         dfdq(1,3) = 0._RP
         dfdq(1,4) = 0._RP
         dfdq(1,5) = 0._RP
         
         dfdq(2,1) = -u*u + 0.5_RP*gammaMinus1*V2
         dfdq(2,2) = (3._RP - gamma) * u
         dfdq(2,3) = -gammaMinus1 * v
         dfdq(2,4) = -gammaMinus1 * w
         dfdq(2,5) = gammaMinus1
         
         dfdq(3,1) = -u*v
         dfdq(3,2) = v
         dfdq(3,3) = u
         dfdq(3,4) = 0._RP
         dfdq(3,5) = 0._RP
         
         dfdq(4,1) = -u*w
         dfdq(4,2) = w
         dfdq(4,3) = 0._RP
         dfdq(4,4) = u
         dfdq(4,5) = 0._RP
         
         dfdq(5,1) = u * (0.5_RP*gammaMinus1*V2 - H)
         dfdq(5,2) = H - gammaMinus1 * u*u
         dfdq(5,3) = -gammaMinus1 * u*v
         dfdq(5,4) = -gammaMinus1 * u*w
         dfdq(5,5) = gamma * u
         
!
!        Flux in the y direction (g)
!        ---------------------------
         
         dgdq(1,1) = 0._RP
         dgdq(1,2) = 0._RP
         dgdq(1,3) = 1._RP
         dgdq(1,4) = 0._RP
         dgdq(1,5) = 0._RP
         
         dgdq(2,1) = -u*v
         dgdq(2,2) = v
         dgdq(2,3) = u
         dgdq(2,4) = 0._RP
         dgdq(2,5) = 0._RP
         
         dgdq(3,1) = -v*v + 0.5_RP*gammaMinus1*V2
         dgdq(3,2) = -gammaMinus1 * u
         dgdq(3,3) = (3._RP - gamma) * v
         dgdq(3,4) = -gammaMinus1 * w
         dgdq(3,5) = gammaMinus1
         
         dgdq(4,1) = -v*w
         dgdq(4,2) = 0._RP
         dgdq(4,3) = w
         dgdq(4,4) = v
         dgdq(4,5) = 0._RP
         
         dgdq(5,1) = v * (0.5_RP*gammaMinus1*V2 - H)
         dgdq(5,2) = -gammaMinus1 * u*v
         dgdq(5,3) = H - gammaMinus1 * v*v
         dgdq(5,4) = -gammaMinus1 * v*w
         dgdq(5,5) = gamma * v
!
!        Flux in the z direction (h)
!        ---------------------------
         
         dhdq(1,1) = 0._RP
         dhdq(1,2) = 0._RP
         dhdq(1,3) = 0._RP
         dhdq(1,4) = 1._RP
         dhdq(1,5) = 0._RP
         
         dhdq(2,1) = -u*w
         dhdq(2,2) = w
         dhdq(2,3) = 0._RP
         dhdq(2,4) = u
         dhdq(2,5) = 0._RP
         
         dhdq(3,1) = -v*w
         dhdq(3,2) = 0._RP
         dhdq(3,3) = w
         dhdq(3,4) = v
         dhdq(3,5) = 0._RP
         
         dhdq(4,1) = -w*w + 0.5_RP*gammaMinus1*V2
         dhdq(4,2) = -gammaMinus1 * u
         dhdq(4,3) = -gammaMinus1 * v
         dhdq(4,4) = (3._RP - gamma) * w
         dhdq(4,5) = gammaMinus1
         
         dhdq(5,1) = w * (0.5_RP*gammaMinus1*V2 - H)
         dhdq(5,2) = -gammaMinus1 * u*w
         dhdq(5,3) = -gammaMinus1 * v*w
         dhdq(5,4) = H - gammaMinus1 * w*w
         dhdq(5,5) = gamma * w
         
         end associate
         
      end subroutine InviscidJacobian
!
!//////////////////////////////////////////////////////////////////////////////////////////
!
!>        VISCOUS FLUXES
!         --------------
!
!//////////////////////////////////////////////////////////////////////////////////////////
!
      pure subroutine ViscousFlux0D_STATE(nEqn, nGradEqn, Q, Q_x, Q_y, Q_z, mu, beta, kappa, F)
         implicit none
         integer,       intent(in)  :: nEqn
         integer,       intent(in)  :: nGradEqn
         real(kind=RP), intent(in)  :: Q   (1:nEqn     )
         real(kind=RP), intent(in)  :: Q_x (1:nGradEqn)
         real(kind=RP), intent(in)  :: Q_y (1:nGradEqn)
         real(kind=RP), intent(in)  :: Q_z (1:nGradEqn)
         real(kind=RP), intent(in)  :: mu
         real(kind=RP), intent(in)  :: beta
         real(kind=RP), intent(in)  :: kappa
         real(kind=RP), intent(out) :: F(1:nEqn, 1:NDIM)
!
!        ---------------
!        Local variables
!        ---------------
!
         real(kind=RP)                    :: T , sutherLaw
         real(kind=RP)                    :: divV
         real(kind=RP)                    :: u , v , w
         real(kind=RP)                    :: invRho, uDivRho(NDIM), u_x(NDIM), u_y(NDIM), u_z(NDIM), nablaT(NDIM)

         invRho  = 1.0_RP / Q(IRHO)

         u = Q(IRHOU) * invRho
         v = Q(IRHOV) * invRho
         w = Q(IRHOW) * invRho
         
         uDivRho = [u * invRho, v * invRho, w * invRho]
         
         u_x = invRho * Q_x(IRHOU:IRHOW) - uDivRho * Q_x(IRHO)
         u_y = invRho * Q_y(IRHOU:IRHOW) - uDivRho * Q_y(IRHO)
         u_z = invRho * Q_z(IRHOU:IRHOW) - uDivRho * Q_z(IRHO)
         
         nablaT(IX) = thermodynamics % gammaMinus1*dimensionless % gammaM2*(invRho*Q_x(IRHOE) - Q(IRHOE)*invRho*invRho*Q_x(IRHO) - u*u_x(IX)-v*u_x(IY)-w*u_x(IZ))
         nablaT(IY) = thermodynamics % gammaMinus1*dimensionless % gammaM2*(invRho*Q_y(IRHOE) - Q(IRHOE)*invRho*invRho*Q_y(IRHO) - u*u_y(IX)-v*u_y(IY)-w*u_y(IZ))
         nablaT(IZ) = thermodynamics % gammaMinus1*dimensionless % gammaM2*(invRho*Q_z(IRHOE) - Q(IRHOE)*invRho*invRho*Q_z(IRHO) - u*u_z(IX)-v*u_z(IY)-w*u_z(IZ))
         
         T     = Temperature(Q)
         sutherLaw = SutherlandsLaw(T)

         divV = U_x(IX) + U_y(IY) + U_z(IZ)

         F(IRHO,IX)  = 0.0_RP
         F(IRHOU,IX) = mu * sutherLaw * (2.0_RP * U_x(IX) - 2.0_RP/3.0_RP * divV ) + beta * divV
         F(IRHOV,IX) = mu * sutherLaw * ( U_x(IY) + U_y(IX) ) 
         F(IRHOW,IX) = mu * sutherLaw * ( U_x(IZ) + U_z(IX) ) 
         F(IRHOE,IX) = F(IRHOU,IX) * u + F(IRHOV,IX) * v + F(IRHOW,IX) * w + kappa * sutherLaw * nablaT(IX) 

         F(IRHO,IY) = 0.0_RP
         F(IRHOU,IY) = F(IRHOV,IX) 
         F(IRHOV,IY) = mu * sutherLaw * (2.0_RP * U_y(IY) - 2.0_RP / 3.0_RP * divV ) + beta * divV
         F(IRHOW,IY) = mu * sutherLaw * ( U_y(IZ) + U_z(IY) ) 
         F(IRHOE,IY) = F(IRHOU,IY) * u + F(IRHOV,IY) * v + F(IRHOW,IY) * w + kappa * sutherLaw * nablaT(IY)

         F(IRHO,IZ) = 0.0_RP
         F(IRHOU,IZ) = F(IRHOW,IX) 
         F(IRHOV,IZ) = F(IRHOW,IY) 
         F(IRHOW,IZ) = mu * sutherLaw * ( 2.0_RP * U_z(IZ) - 2.0_RP / 3.0_RP * divV ) + beta * divV
         F(IRHOE,IZ) = F(IRHOU,IZ) * u + F(IRHOV,IZ) * v + F(IRHOW,IZ) * w + kappa * sutherLaw * nablaT(IZ)

         ! with Pr = constant, dmudx = dkappadx
      end subroutine ViscousFlux0D_STATE

      pure subroutine ViscousFlux2D_STATE( nEqn, nGradEqn, N, Q, Q_x, Q_y, Q_z, mu, beta, kappa, F)
         implicit none
         integer,       intent(in)  :: nEqn
         integer,       intent(in)  :: nGradEqn
         integer         , intent(in)  :: N(2)
         real(kind=RP),    intent(in)  :: Q  (1:nEqn, 0:N(1), 0:N(2))
         real(kind=RP),    intent(in)  :: Q_x(1:nGradEqn, 0:N(1), 0:N(2) )
         real(kind=RP),    intent(in)  :: Q_y(1:nGradEqn, 0:N(1), 0:N(2) )
         real(kind=RP),    intent(in)  :: Q_z(1:nGradEqn, 0:N(1), 0:N(2) )
         real(kind=RP),    intent(in)  :: mu  (0:N(1), 0:N(2))
         real(kind=RP),    intent(in)  :: beta(0:N(1), 0:N(2))
         real(kind=RP),    intent(in)  :: kappa(0:N(1), 0:N(2))
         real(kind=RP),    intent(out) :: F   (1:nEqn, 1:NDIM, 0:N(1), 0:N(2))
!
!        ---------------
!        Local variables
!        ---------------
!
         real(kind=RP) :: invRho, uDivRho(NDIM), u_x(NDIM), u_y(NDIM), u_z(NDIM), nablaT(NDIM)
         real(kind=RP) :: T , sutherLaw
         real(kind=RP) :: divV
         real(kind=RP) :: u(NDIM)
         integer       :: i , j , k

         associate( gammaM2 => dimensionless % gammaM2, &
                    gammaMinus1 => thermodynamics % gammaMinus1 ) 

         do j = 0, N(2) ; do i = 0, N(1)
!
!           Compute the density inverse and velocities
!           ------------------------------------------
            invRho  = 1.0_RP / Q(IRHO,i,j)
            u       = Q(IRHOU:IRHOW,i,j) * invRho
            uDivRho = u * invRho
   
            T = gammaM2 * gammaMinus1 * ( invRho * Q(IRHOE,i,j) - 0.5_RP * ( u(IX) * u(IX) + u(IY) * u(IY) + u(IZ) * u(IZ) ) )
            sutherLaw = SutherlandsLaw(T)
            
            u_x = invRho * Q_x(IRHOU:IRHOW,i,j) - uDivRho * Q_x(IRHO,i,j)
            u_y = invRho * Q_y(IRHOU:IRHOW,i,j) - uDivRho * Q_y(IRHO,i,j)
            u_z = invRho * Q_z(IRHOU:IRHOW,i,j) - uDivRho * Q_z(IRHO,i,j)
   
            nablaT(IX) =  gammaMinus1* gammaM2*(invRho*Q_x(IRHOE,i,j) - Q(IRHOE,i,j)*invRho*invRho*Q_x(IRHO,i,j) - u(IX)*u_x(IX)-u(IY)*u_x(IY)-u(IZ)*u_x(IZ))
            nablaT(IY) =  gammaMinus1* gammaM2*(invRho*Q_y(IRHOE,i,j) - Q(IRHOE,i,j)*invRho*invRho*Q_y(IRHO,i,j) - u(IX)*u_y(IX)-u(IY)*u_y(IY)-u(IZ)*u_y(IZ))
            nablaT(IZ) =  gammaMinus1* gammaM2*(invRho*Q_z(IRHOE,i,j) - Q(IRHOE,i,j)*invRho*invRho*Q_z(IRHO,i,j) - u(IX)*u_z(IX)-u(IY)*u_z(IY)-u(IZ)*u_z(IZ))
            
            divV = U_x(IX) + U_y(IY) + U_z(IZ)
   
            F(IRHO ,IX,i,j) = 0.0_RP
            F(IRHOU,IX,i,j) = mu(i,j) * sutherLaw * (2.0_RP * U_x(IX) - 2.0_RP/3.0_RP * divV ) + beta(i,j) * divV
            F(IRHOV,IX,i,j) = mu(i,j) * sutherLaw * ( U_x(IY) + U_y(IX) ) 
            F(IRHOW,IX,i,j) = mu(i,j) * sutherLaw * ( U_x(IZ) + U_z(IX) ) 
            F(IRHOE,IX,i,j) = F(IRHOU,IX,i,j) * u(IX) + F(IRHOV,IX,i,j) * u(IY) + F(IRHOW,IX,i,j) * u(IZ) &
                  + sutherLaw * kappa(i,j) * nablaT(IX)
   
            F(IRHO, IY,i,j) = 0.0_RP
            F(IRHOU,IY,i,j) = mu(i,j) * sutherLaw * ( U_x(IY) + U_y(IX) )  
            F(IRHOV,IY,i,j) = mu(i,j) * sutherLaw * (2.0_RP * U_y(IY) - 2.0_RP / 3.0_RP * divV ) + beta(i,j) * divV 
            F(IRHOW,IY,i,j) = mu(i,j) * sutherLaw * ( U_y(IZ) + U_z(IY) ) 
            F(IRHOE,IY,i,j) = F(IRHOU,IY,i,j) * u(IX) + F(IRHOV,IY,i,j) * u(IY) + F(IRHOW,IY,i,j) * u(IZ) &
                  + sutherLaw * kappa(i,j) * nablaT(IY)
   
            F(IRHO, IZ,i,j ) = 0.0_RP
            F(IRHOU,IZ,i,j) = mu(i,j) * sutherLaw * ( U_x(IZ) + U_z(IX) ) 
            F(IRHOV,IZ,i,j) = mu(i,j) * sutherLaw * ( U_y(IZ) + U_z(IY) ) 
            F(IRHOW,IZ,i,j) = mu(i,j) * sutherLaw * ( 2.0_RP * U_z(IZ) - 2.0_RP / 3.0_RP * divV ) + beta(i,j) * divV   
            F(IRHOE,IZ,i,j) = F(IRHOU,IZ,i,j) * u(IX) + F(IRHOV,IZ,i,j) * u(IY) + F(IRHOW,IZ,i,j) * u(IZ) &
                  + sutherLaw * kappa(i,j) * nablaT(IZ)
   
         end do    ; end do

         end associate

      end subroutine ViscousFlux2D_STATE

      pure subroutine ViscousFlux3D_STATE( nEqn, nGradEqn, N, Q, Q_x, Q_y, Q_z, mu, beta, kappa, F)
         implicit none
         integer,       intent(in)  :: nEqn
         integer,       intent(in)  :: nGradEqn
         integer         , intent(in)  :: N(3)
         real(kind=RP),    intent(in)  :: Q  (1:nEqn, 0:N(1), 0:N(2), 0:N(3))
         real(kind=RP),    intent(in)  :: Q_x(1:nGradEqn, 0:N(1), 0:N(2), 0:N(3) )
         real(kind=RP),    intent(in)  :: Q_y(1:nGradEqn, 0:N(1), 0:N(2), 0:N(3) )
         real(kind=RP),    intent(in)  :: Q_z(1:nGradEqn, 0:N(1), 0:N(2), 0:N(3) )
         real(kind=RP),    intent(in)  :: mu  (0:N(1), 0:N(2), 0:N(3))
         real(kind=RP),    intent(in)  :: beta(0:N(1), 0:N(2), 0:N(3))
         real(kind=RP),    intent(in)  :: kappa(0:N(1), 0:N(2), 0:N(3))
         real(kind=RP),    intent(out) :: F   (1:nEqn, 0:N(1), 0:N(2), 0:N(3), 1:NDIM )
!
!        ---------------
!        Local variables
!        ---------------
!
         real(kind=RP) :: invRho, uDivRho(NDIM), u_x(NDIM), u_y(NDIM), u_z(NDIM), nablaT(NDIM)
         real(kind=RP) :: T, sutherLaw
         real(kind=RP) :: divV
         real(kind=RP) :: u(NDIM)
         integer       :: i , j , k

         associate( gammaM2 => dimensionless % gammaM2, &
                    gammaMinus1 => thermodynamics % gammaMinus1 ) 

         do k = 0, N(3) ; do j = 0, N(2) ; do i = 0, N(1)
!
!           Compute the density inverse and velocities
!           ------------------------------------------
            invRho  = 1.0_RP / Q(IRHO,i,j,k)
            u       = Q(IRHOU:IRHOW,i,j,k) * invRho
            uDivRho = u * invRho
   
            T = gammaM2 * gammaMinus1 * ( invRho * Q(IRHOE,i,j,k) - 0.5_RP * ( u(IX) * u(IX) + u(IY) * u(IY) + u(IZ) * u(IZ) ) )
            sutherLaw = SutherlandsLaw(T)
            
            u_x = invRho * Q_x(IRHOU:IRHOW,i,j,k) - uDivRho * Q_x(IRHO,i,j,k)
            u_y = invRho * Q_y(IRHOU:IRHOW,i,j,k) - uDivRho * Q_y(IRHO,i,j,k)
            u_z = invRho * Q_z(IRHOU:IRHOW,i,j,k) - uDivRho * Q_z(IRHO,i,j,k)
   
            nablaT(IX) =  gammaMinus1* gammaM2*(invRho*Q_x(IRHOE,i,j,k) - Q(IRHOE,i,j,k)*invRho*invRho*Q_x(IRHO,i,j,k) - u(IX)*u_x(IX)-u(IY)*u_x(IY)-u(IZ)*u_x(IZ))
            nablaT(IY) =  gammaMinus1* gammaM2*(invRho*Q_y(IRHOE,i,j,k) - Q(IRHOE,i,j,k)*invRho*invRho*Q_y(IRHO,i,j,k) - u(IX)*u_y(IX)-u(IY)*u_y(IY)-u(IZ)*u_y(IZ))
            nablaT(IZ) =  gammaMinus1* gammaM2*(invRho*Q_z(IRHOE,i,j,k) - Q(IRHOE,i,j,k)*invRho*invRho*Q_z(IRHO,i,j,k) - u(IX)*u_z(IX)-u(IY)*u_z(IY)-u(IZ)*u_z(IZ))
            
            divV = U_x(IX) + U_y(IY) + U_z(IZ)
!
!           Compute the fluxes
!           ------------------
   
            F(IRHO,i,j,k ,IX) = 0.0_RP
            F(IRHOU,i,j,k,IX) = mu(i,j,k) * sutherLaw * (2.0_RP * U_x(IX) - 2.0_RP/3.0_RP * divV ) + beta(i,j,k) * divV
            F(IRHOV,i,j,k,IX) = mu(i,j,k) * sutherLaw * ( U_x(IY) + U_y(IX) ) 
            F(IRHOW,i,j,k,IX) = mu(i,j,k) * sutherLaw * ( U_x(IZ) + U_z(IX) ) 
            F(IRHOE,i,j,k,IX) = F(IRHOU,i,j,k,IX) * u(IX) + F(IRHOV,i,j,k,IX) * u(IY) + F(IRHOW,i,j,k,IX) * u(IZ) &
                  + sutherLaw * kappa(i,j,k) * nablaT(IX) 
                  
            F(IRHO,i,j,k ,IY) = 0.0_RP
            F(IRHOU,i,j,k,IY) = mu(i,j,k) * sutherLaw * ( U_x(IY) + U_y(IX) )  
            F(IRHOV,i,j,k,IY) = mu(i,j,k) * sutherLaw * (2.0_RP * U_y(IY) - 2.0_RP / 3.0_RP * divV ) + beta(i,j,k) * divV 
            F(IRHOW,i,j,k,IY) = mu(i,j,k) * sutherLaw * ( U_y(IZ) + U_z(IY) ) 
            F(IRHOE,i,j,k,IY) = F(IRHOU,i,j,k,IY) * u(IX) + F(IRHOV,i,j,k,IY) * u(IY) + F(IRHOW,i,j,k,IY) * u(IZ) &
                  + sutherLaw * kappa(i,j,k) * nablaT(IY) 
                  
            F(IRHO,i,j,k,IZ ) = 0.0_RP
            F(IRHOU,i,j,k,IZ) = mu(i,j,k) * sutherLaw * ( U_x(IZ) + U_z(IX) ) 
            F(IRHOV,i,j,k,IZ) = mu(i,j,k) * sutherLaw * ( U_y(IZ) + U_z(IY) ) 
            F(IRHOW,i,j,k,IZ) = mu(i,j,k) * sutherLaw * ( 2.0_RP * U_z(IZ) - 2.0_RP / 3.0_RP * divV ) + beta(i,j,k) * divV 
            F(IRHOE,i,j,k,IZ) = F(IRHOU,i,j,k,IZ) * u(IX) + F(IRHOV,i,j,k,IZ) * u(IY) + F(IRHOW,i,j,k,IZ) * u(IZ) &
                  + sutherLaw * kappa(i,j,k) * nablaT(IZ) 
         end do      ; end do    ; end do

         end associate

      end subroutine ViscousFlux3D_STATE
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!
!     ------------------------------------------------------------------------------------------
!     Subroutine for computing the Jacobians of the viscous fluxes 
!
!     1. Jacobian with respect to the gradients of the conserved variables: df/d(∇q)
!        Every direction of the viscous flux can be expressed as
!
!        f_i = \sum_j df_dgradq(:,:,j,i) dq/dx_j
!
!        In Navier-Stokes, this dependence is linear. Therefore:
!
!              df_dgradq         := df/d(∇q)
!                                   d f_i(2)   |
!              df_dgradq(2,4,j,i) = ---------- |
!                                   d(∇q)_j(4) |q=cons,
!			where (∇q)_j = dq/dx_j
!        
!			Following Hartmann's notation, G_{ij} = df_dgradq(:,:,j,i). --> R. Hartmann. "Discontinuous Galerkin methods for compressible flows: higher order accuracy, error estimation and adaptivity". 2005.
!
!     2. Jacobian with respect to the conserved variables: df/dq
!
!				 	df_dq       := df/d(∇q)
!                             d f_i(2) |
!              df_dq(2,4,i) = -------- |
!                             dq(4)    |∇q=cons
!
!     NOTE 1: Here the thermal conductivity and the viscosity are computed using Sutherland's law!     
!     NOTE 2: The dependence of the temperature on q is not considered in Sutherland's law
!
!     ***** This routine is necessary for computing the analytical Jacobian. *****
!     ------------------------------------------------------------------------------------------
      pure subroutine ViscousJacobian(q, Q_x, Q_y, Q_z, df_dgradq, df_dq)
         implicit none
         !-------------------------------------------------
         real(kind=RP), intent(in)  :: q(NCONS)                      !< Conserved variables state
         real(kind=RP), intent(in)  :: Q_x (1:NGRAD)
         real(kind=RP), intent(in)  :: Q_y (1:NGRAD)
         real(kind=RP), intent(in)  :: Q_z (1:NGRAD) ! , intent(in)
         real(kind=RP), intent(out) :: df_dgradq(NCONS,NCONS,NDIM,NDIM)
         real(kind=RP), intent(out) :: df_dq    (NCONS,NCONS,NDIM)
         !-------------------------------------------------
         real(kind=RP)            :: T , sutherLaw
         real(kind=RP)            :: u , v , w, E, u2, v2, w2, Vel2
         real(kind=RP)            :: vv_x, vv_y, vv_z
         real(kind=RP)            :: V_gradU, V_gradV, V_gradW, gradE(3)
         real(kind=RP)            :: gamma_Pr
         real(kind=RP)            :: rho_DivV, V_gradRho
         real(kind=RP)            :: invRho, invRho2, uDivRho(NDIM), U_x(NDIM), U_y(NDIM), U_z(NDIM)
         real(kind=RP)            :: F(NCONS,NDIM)
         real(kind=RP)            :: dMu_dQ(NCONS)
         real(kind=RP), parameter :: lambda = 1._RP/3._RP
         real(kind=RP), parameter :: f4_3 = 4._RP/3._RP
         real(kind=RP), parameter :: f2_3 = 2._RP/3._RP
         !-------------------------------------------------
         
         invRho  = 1._RP / Q(IRHO)
         invRho2 = invRho * invRho
         
         uDivRho = [Q(IRHOU) , Q(IRHOV) , Q(IRHOW) ] * invRho2
         
         u_x = invRho * Q_x(IRHOU:IRHOW) - uDivRho * Q_x(IRHO)
         u_y = invRho * Q_y(IRHOU:IRHOW) - uDivRho * Q_y(IRHO)
         u_z = invRho * Q_z(IRHOU:IRHOW) - uDivRho * Q_z(IRHO)
         
         u  = Q(IRHOU) * invRho
         v  = Q(IRHOV) * invRho
         w  = Q(IRHOW) * invRho
         
         E  = Q(IRHOE) * invRho
         u2 = u*u
         v2 = v*v
         w2 = w*w
         Vel2 = u2 + v2 + w2

         T     = Temperature(q)
         sutherLaw = SutherlandsLaw(T)
         
         associate ( gamma => thermodynamics % gamma, & 
                     gammaM2 => dimensionless % gammaM2, &
                     gammaMinus1 => thermodynamics % gammaMinus1, &
                     Re    => dimensionless % Re    , &
                     Pr    => dimensionless % Pr ) 
         
         gamma_Pr = gamma/Pr
         
!
!        *****************************
!        Derivative with respect to ∇q
!        *****************************
!
         
!
!        Flux in the x direction: f = G_{1:} · ∇q
!        ----------------------------------------
         
         ! G_{11}
         df_dgradq(:,1,1,1) = (/ 0._RP , -f4_3*u ,      -v ,      -w , -(f4_3*u2 + v2 + w2 + gamma_Pr*(E - Vel2)) /)
         df_dgradq(:,2,1,1) = (/ 0._RP ,  f4_3   ,   0._RP ,   0._RP , u * (  f4_3 - gamma_Pr)                           /)
         df_dgradq(:,3,1,1) = (/ 0._RP ,   0._RP ,   1._RP ,   0._RP , v * (1.0_RP - gamma_Pr)                           /)
         df_dgradq(:,4,1,1) = (/ 0._RP ,   0._RP ,   0._RP ,   1._RP , w * (1.0_RP - gamma_Pr)                           /)
         df_dgradq(:,5,1,1) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,               gamma_Pr                            /)
         
         ! G_{12}
         df_dgradq(:,1,2,1) = (/ 0._RP ,  f2_3*v ,      -u ,   0._RP , -lambda*u*v /)
         df_dgradq(:,2,2,1) = (/ 0._RP ,   0._RP ,   1._RP ,   0._RP ,       v   /)
         df_dgradq(:,3,2,1) = (/ 0._RP , -f2_3   ,   0._RP ,   0._RP , -f2_3*u   /)
         df_dgradq(:,4,2,1) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         df_dgradq(:,5,2,1) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         
         ! G_{13}
         df_dgradq(:,1,3,1) = (/ 0._RP ,  f2_3*w ,   0._RP ,      -u , -lambda*u*w /)
         df_dgradq(:,2,3,1) = (/ 0._RP ,   0._RP ,   0._RP ,   1._RP ,       w   /)
         df_dgradq(:,3,3,1) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         df_dgradq(:,4,3,1) = (/ 0._RP , -f2_3   ,   0._RP ,   0._RP , -f2_3*u   /)
         df_dgradq(:,5,3,1) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         
!
!        Flux in the y direction: g = G_{2:} · ∇q
!        ----------------------------------------
         
         ! G_{21}
         df_dgradq(:,1,1,2) = (/ 0._RP ,      -v ,  f2_3*u ,   0._RP , -lambda*u*v /)
         df_dgradq(:,2,1,2) = (/ 0._RP ,   0._RP , -f2_3   ,   0._RP , -f2_3*v   /)
         df_dgradq(:,3,1,2) = (/ 0._RP ,   1._RP ,   0._RP ,   0._RP ,       u   /)
         df_dgradq(:,4,1,2) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         df_dgradq(:,5,1,2) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         
         ! G_{22}
         df_dgradq(:,1,2,2) = (/ 0._RP ,      -u , -f4_3*v ,      -w , -(u2 + f4_3*v2 + w2 + gamma_Pr*(E - Vel2)) /)
         df_dgradq(:,2,2,2) = (/ 0._RP ,   1._RP ,   0._RP ,   0._RP , u * (1.0_RP - gamma_Pr)                           /)
         df_dgradq(:,3,2,2) = (/ 0._RP ,   0._RP ,  f4_3   ,   0._RP , v * (  f4_3 - gamma_Pr)                           /)
         df_dgradq(:,4,2,2) = (/ 0._RP ,   0._RP ,   0._RP ,   1._RP , w * (1.0_RP - gamma_Pr)                           /)
         df_dgradq(:,5,2,2) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,               gamma_Pr                            /)
         
         ! G_{23}
         df_dgradq(:,1,3,2) = (/ 0._RP ,   0._RP ,  f2_3*w ,      -v , -lambda*v*w /)
         df_dgradq(:,2,3,2) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         df_dgradq(:,3,3,2) = (/ 0._RP ,   0._RP ,   0._RP ,   1._RP ,       w   /)
         df_dgradq(:,4,3,2) = (/ 0._RP ,   0._RP , -f2_3   ,   0._RP , -f2_3*v   /)
         df_dgradq(:,5,3,2) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         
!
!        Flux in the z direction: h = G_{3:} · ∇q
!        ----------------------------------------
         
         ! G_{31}
         df_dgradq(:,1,1,3) = (/ 0._RP ,      -w ,   0._RP ,  f2_3*u , -lambda*u*w /)
         df_dgradq(:,2,1,3) = (/ 0._RP ,   0._RP ,   0._RP , -f2_3   , -f2_3*w   /)
         df_dgradq(:,3,1,3) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         df_dgradq(:,4,1,3) = (/ 0._RP ,   1._RP ,   0._RP ,   0._RP ,       u   /)
         df_dgradq(:,5,1,3) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         
         ! G_{32}
         df_dgradq(:,1,2,3) = (/ 0._RP ,   0._RP ,      -w ,  f2_3*v , -lambda*v*w /)
         df_dgradq(:,2,2,3) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         df_dgradq(:,3,2,3) = (/ 0._RP ,   0._RP ,   0._RP , -f2_3   , -f2_3*w   /)
         df_dgradq(:,4,2,3) = (/ 0._RP ,   0._RP ,   1._RP ,   0._RP ,       v   /)
         df_dgradq(:,5,2,3) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,   0._RP   /)
         
         ! G_{33}
         df_dgradq(:,1,3,3) = (/ 0._RP ,      -u ,      -v , -f4_3*w , -(u2 + v2 + f4_3*w2 + gamma_Pr*(E - Vel2)) /)
         df_dgradq(:,2,3,3) = (/ 0._RP ,   1._RP ,   0._RP ,   0._RP , u * (1.0_RP - gamma_Pr)                           /)
         df_dgradq(:,3,3,3) = (/ 0._RP ,   0._RP ,   1._RP ,   0._RP , v * (1.0_RP - gamma_Pr)                           /)
         df_dgradq(:,4,3,3) = (/ 0._RP ,   0._RP ,   0._RP ,  f4_3   , w * (  f4_3 - gamma_Pr)                           /)
         df_dgradq(:,5,3,3) = (/ 0._RP ,   0._RP ,   0._RP ,   0._RP ,               gamma_Pr                            /)
         
!
!        Scale with mu/(rho*Re) .or. kappa/(rho*Re)
!        ------------------------------------------
         
         df_dgradq = df_dgradq * sutherLaw / ( Q(IRHO) * Re )
         
!
!        ****************************
!        Derivative with respect to q
!        ****************************
!
!        Auxiliar variables
!        ------------------
         
         rho_DivV      = Q(IRHO) * ( U_x(IX) + U_y(IY) + U_z(IZ) )       ! rho ∇ · v
         V_gradRho     = u * Q_x(IRHO) + v * Q_y(IRHO) + w * Q_z(IRHO)   ! v · ∇rho
         V_gradU       = u * U_x(IX) + v * U_y(IX) + w * U_z(IX)
         V_gradV       = u * U_x(IY) + v * U_y(IY) + w * U_z(IY)
         V_gradW       = u * U_x(IZ) + v * U_y(IZ) + w * U_z(IZ)
         
         vv_x = 2._RP * Q(IRHO) * ( u * U_x(IX) + v * U_x(IY) + w * U_x(IZ) )
         vv_y = 2._RP * Q(IRHO) * ( u * U_y(IX) + v * U_y(IY) + w * U_y(IZ) )
         vv_z = 2._RP * Q(IRHO) * ( u * U_z(IX) + v * U_z(IY) + w * U_z(IZ) )
         
         gradE(1) = Q_x(IRHOE) * invRho - E * invRho * Q_x(IRHO)
         gradE(2) = Q_y(IRHOE) * invRho - E * invRho * Q_y(IRHO)
         gradE(3) = Q_z(IRHOE) * invRho - E * invRho * Q_z(IRHO)
         
!        Jacobian entries
!        ----------------
         
         ! A_1
         df_dq(:,1,1) = (/ 0._RP , & 
                           2._RP * lambda * (rho_DivV - V_gradRho) + 2._RP * ( u * Q_x(IRHO) - Q(IRHO) * U_x(IX) ), &
                           u * Q_y(IRHO) + v * Q_x(IRHO) - Q(IRHO) * ( U_y(IX) + U_x(IY)) , &
                           u * Q_z(IRHO) + w * Q_x(IRHO) - Q(IRHO) * ( U_z(IX) + U_x(IZ)) , &
                           (1._RP - gamma_Pr) * ( Vel2*Q_x(IRHO) - vv_x ) + lambda * u * (4._RP*rho_DivV + V_gradRho) &
                                - 2 * Q(IRHO) * V_gradU + gamma_Pr * ( E * Q_x(IRHO) - Q(IRHO) * gradE(1) ) /)
         
         df_dq(:,2,1) = (/ 0._RP , -4._RP*lambda*Q_x(IRHO) , -Q_y(IRHO) , -Q_z(IRHO) , -u * (lambda - gamma_Pr) * Q_x(IRHO) + Q(IRHO) * ( 2._RP - gamma_Pr) * U_x(IX) - V_gradRho - 2._RP * lambda * rho_DivV /)
         df_dq(:,3,1) = (/ 0._RP ,  2._RP*lambda*Q_y(IRHO) , -Q_x(IRHO) , 0._RP       , (1._RP - gamma_Pr) * (Q(IRHO) * U_x(IY) - v * Q_x(IRHO)) + Q(IRHO) * U_y(IX) + 2._RP * lambda * u * Q_y(IRHO) /)
         df_dq(:,4,1) = (/ 0._RP ,  2._RP*lambda*Q_z(IRHO) , 0._RP       , -Q_x(IRHO) , (1._RP - gamma_Pr) * (Q(IRHO) * U_x(IZ) - w * Q_x(IRHO)) + Q(IRHO) * U_z(IX) + 2._RP * lambda * u * Q_z(IRHO) /)
         df_dq(:,5,1) = (/ 0._RP , 0._RP                    , 0._RP       , 0._RP       , -gamma_Pr * Q_x(IRHO) /)
         
         ! A_2
         df_dq(:,1,2) = (/ 0._RP , & 
                           v * Q_x(IRHO) + u * Q_y(IRHO) - Q(IRHO) * ( U_x(IY) + U_y(IX)) , &
                           2._RP * lambda * (rho_DivV - V_gradRho) + 2._RP * ( v * Q_y(IRHO) - Q(IRHO) * U_y(IY) ), &
                           v * Q_z(IRHO) + w * Q_y(IRHO) - Q(IRHO) * ( U_z(IY) + U_y(IZ)) , &
                           (1._RP - gamma_Pr) * ( Vel2*Q_y(IRHO) - vv_y ) + lambda * v * (4._RP*rho_DivV + V_gradRho) &
                                - 2 * Q(IRHO) * V_gradV + gamma_Pr * ( E * Q_y(IRHO) - Q(IRHO) * gradE(2) ) /)
         
         df_dq(:,2,2) = (/ 0._RP , -Q_y(IRHO) ,  2._RP*lambda*Q_x(IRHO) , 0._RP       , (1._RP - gamma_Pr) * (Q(IRHO) * U_y(IX) - u * Q_y(IRHO)) + Q(IRHO) * U_x(IY) + 2._RP * lambda * v * Q_x(IRHO) /)
         df_dq(:,3,2) = (/ 0._RP , -Q_x(IRHO) , -4._RP*lambda*Q_y(IRHO) , -Q_z(IRHO) , -v * (lambda - gamma_Pr) * Q_y(IRHO) + Q(IRHO) * ( 2._RP - gamma_Pr) * U_y(IY) - V_gradRho - 2._RP * lambda * rho_DivV /)
         df_dq(:,4,2) = (/ 0._RP , 0._RP       ,  2._RP*lambda*Q_z(IRHO) , -Q_y(IRHO) , (1._RP - gamma_Pr) * (Q(IRHO) * U_y(IZ) - w * Q_y(IRHO)) + Q(IRHO) * U_z(IY) + 2._RP * lambda * v * Q_z(IRHO) /)
         df_dq(:,5,2) = (/ 0._RP , 0._RP       , 0._RP                    , 0._RP       , -gamma_Pr * Q_y(IRHO) /)
         
         ! A_3
         df_dq(:,1,3) = (/ 0._RP , & 
                           w * Q_x(IRHO) + u * Q_z(IRHO) - Q(IRHO) * ( U_x(IZ) + U_z(IX)) , &
                           w * Q_y(IRHO) + v * Q_z(IRHO) - Q(IRHO) * ( U_y(IZ) + U_z(IY)) , &
                           2._RP * lambda * (rho_DivV - V_gradRho) + 2._RP * ( w * Q_z(IRHO) - Q(IRHO) * U_z(IZ) ), &
                           (1._RP - gamma_Pr) * ( Vel2*Q_z(IRHO) - vv_z ) + lambda * w * (4._RP*rho_DivV + V_gradRho) &
                                - 2 * Q(IRHO) * V_gradW + gamma_Pr * ( E * Q_z(IRHO) - Q(IRHO) * gradE(3) ) /)
         
         df_dq(:,2,3) = (/ 0._RP , -Q_z(IRHO) , 0._RP       ,  2._RP*lambda*Q_x(IRHO) , (1._RP - gamma_Pr) * (Q(IRHO) * U_z(IX) - u * Q_z(IRHO)) + Q(IRHO) * U_x(IZ) + 2._RP * lambda * w * Q_x(IRHO) /)
         df_dq(:,3,3) = (/ 0._RP , 0._RP       , -Q_z(IRHO) ,  2._RP*lambda*Q_y(IRHO) , (1._RP - gamma_Pr) * (Q(IRHO) * U_z(IY) - v * Q_z(IRHO)) + Q(IRHO) * U_y(IZ) + 2._RP * lambda * w * Q_y(IRHO) /)
         df_dq(:,4,3) = (/ 0._RP , -Q_x(IRHO) , -Q_y(IRHO) , -4._RP*lambda*Q_z(IRHO) , -w * (lambda - gamma_Pr) * Q_z(IRHO) + Q(IRHO) * ( 2._RP - gamma_Pr) * U_z(IZ) - V_gradRho - 2._RP * lambda * rho_DivV /)
         df_dq(:,5,3) = (/ 0._RP , 0._RP       , 0._RP       , 0._RP                    , -gamma_Pr * Q_z(IRHO) /)
         
!
!        Scale with mu/(rho² Re) .or. kappa/(rho² Re)
!        --------------------------------------------
         
         df_dq = df_dq * sutherLaw / ( Q(IRHO)**2 * Re ) 
         
!
!        Correct with the derivative of the Sutherland's law
!        --------------------------------------------------
         dMu_dQ    = SutherlandsLawDeriv(Q,T)
         
         call ViscousFlux0D_STATE(NCONS, NCONS, Q, Q_x, Q_y, Q_z, dimensionless % mu, 0._RP, dimensionless % kappa, F)
         F = F / sutherLaw
         
         df_dq(:,:,1) = df_dq(:,:,1) + outer_product(F(:,1),dMu_dQ)
         df_dq(:,:,2) = df_dq(:,:,2) + outer_product(F(:,2),dMu_dQ)
         df_dq(:,:,3) = df_dq(:,:,3) + outer_product(F(:,3),dMu_dQ)
         
         end associate
      end subroutine ViscousJacobian
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
      pure subroutine ViscousFlux0D_withSGS(nEqn, nGradEqn, Q, Q_x, Q_y, Q_z, mu, kappa, tauSGS, qSGS, F)
         implicit none
         integer,       intent(in)  :: nEqn
         integer,       intent(in)  :: nGradEqn
         real(kind=RP), intent(in)  :: Q   (1:nEqn     )
         real(kind=RP), intent(in)  :: Q_x (1:nGradEqn)
         real(kind=RP), intent(in)  :: Q_y (1:nGradEqn)
         real(kind=RP), intent(in)  :: Q_z (1:nGradEqn)
         real(kind=RP), intent(in)  :: mu
         real(kind=RP), intent(in)  :: kappa
         real(kind=RP), intent(in)  :: tauSGS(NDIM, NDIM)
         real(kind=RP), intent(in)  :: qSGS(NDIM)
         real(kind=RP), intent(out) :: F(1:nEqn, 1:NDIM)
!
!        ---------------
!        Local variables
!        ---------------
!
         real(kind=RP)                    :: T , sutherLaw
         real(kind=RP)                    :: divV
         real(kind=RP)                    :: u , v , w
         real(kind=RP)                    :: invRho, uDivRho(NDIM), u_x(NDIM), u_y(NDIM), u_z(NDIM), nablaT(NDIM)

         invRho  = 1.0_RP / Q(IRHO)

         u = Q(IRHOU) * invRho
         v = Q(IRHOV) * invRho
         w = Q(IRHOW) * invRho
         
         uDivRho = [u * invRho, v * invRho, w * invRho]
         
         u_x = invRho * Q_x(IRHOU:IRHOW) - uDivRho * Q_x(IRHO)
         u_y = invRho * Q_y(IRHOU:IRHOW) - uDivRho * Q_y(IRHO)
         u_z = invRho * Q_z(IRHOU:IRHOW) - uDivRho * Q_z(IRHO)
         
         nablaT(IX) = thermodynamics % gammaMinus1*dimensionless % gammaM2*(invRho*Q_x(IRHOE) - Q(IRHOE)*invRho*invRho*Q_x(IRHO) - u*u_x(IX)-v*u_x(IY)-w*u_x(IZ))
         nablaT(IY) = thermodynamics % gammaMinus1*dimensionless % gammaM2*(invRho*Q_y(IRHOE) - Q(IRHOE)*invRho*invRho*Q_y(IRHO) - u*u_y(IX)-v*u_y(IY)-w*u_y(IZ))
         nablaT(IZ) = thermodynamics % gammaMinus1*dimensionless % gammaM2*(invRho*Q_z(IRHOE) - Q(IRHOE)*invRho*invRho*Q_z(IRHO) - u*u_z(IX)-v*u_z(IY)-w*u_z(IZ))
         
         T     = Temperature(Q)
         sutherLaw = SutherlandsLaw(T)

         divV = U_x(IX) + U_y(IY) + U_z(IZ)

         F(IRHO,IX)  = 0.0_RP
         F(IRHOU,IX) = mu * sutherLaw * (2.0_RP * U_x(IX) - 2.0_RP/3.0_RP * divV ) - tauSGS(1,1)
         F(IRHOV,IX) = mu * sutherLaw * ( U_x(IY) + U_y(IX) ) - tauSGS(2,1)
         F(IRHOW,IX) = mu * sutherLaw * ( U_x(IZ) + U_z(IX) ) - tauSGS(3,1)
         F(IRHOE,IX) = F(IRHOU,IX) * u + F(IRHOV,IX) * v + F(IRHOW,IX) * w + kappa * sutherLaw * nablaT(IX) - qSGS(1)

         F(IRHO,IY) = 0.0_RP
         F(IRHOU,IY) = F(IRHOV,IX) 
         F(IRHOV,IY) = mu * sutherLaw * (2.0_RP * U_y(IY) - 2.0_RP / 3.0_RP * divV ) - tauSGS(2,2)
         F(IRHOW,IY) = mu * sutherLaw * ( U_y(IZ) + U_z(IY) ) - tauSGS(3,2)
         F(IRHOE,IY) = F(IRHOU,IY) * u + F(IRHOV,IY) * v + F(IRHOW,IY) * w + kappa * sutherLaw * nablaT(IY) - qSGS(2)

         F(IRHO,IZ) = 0.0_RP
         F(IRHOU,IZ) = F(IRHOW,IX) 
         F(IRHOV,IZ) = F(IRHOW,IY) 
         F(IRHOW,IZ) = mu * sutherLaw * ( 2.0_RP * U_z(IZ) - 2.0_RP / 3.0_RP * divV ) - tauSGS(3,3)
         F(IRHOE,IZ) = F(IRHOU,IZ) * u + F(IRHOV,IZ) * v + F(IRHOW,IZ) * w + kappa * sutherLaw * nablaT(IZ) - qSGS(3)

      end subroutine ViscousFlux0D_withSGS

      pure subroutine ViscousFlux2D_withSGS( nEqn, nGradEqn, N, Q, Q_x, Q_y, Q_z, mu, kappa, tauSGS, qSGS, F)
         implicit none
         integer,          intent(in)  :: nEqn
         integer,          intent(in)  :: nGradEqn
         integer         , intent(in)  :: N(2)
         real(kind=RP),    intent(in)  :: Q  (1:nEqn, 0:N(1), 0:N(2))
         real(kind=RP),    intent(in)  :: Q_x(1:nGradEqn, 0:N(1), 0:N(2) )
         real(kind=RP),    intent(in)  :: Q_y(1:nGradEqn, 0:N(1), 0:N(2) )
         real(kind=RP),    intent(in)  :: Q_z(1:nGradEqn, 0:N(1), 0:N(2) )
         real(kind=RP),    intent(in)  :: mu  (0:N(1), 0:N(2))
         real(kind=RP),    intent(in)  :: kappa(0:N(1), 0:N(2))
         real(kind=RP),    intent(in)  :: tauSGS(1:NDIM, 1:NDIM, 0:N(1), 0:N(2))
         real(kind=RP),    intent(in)  :: qSGS(1:NDIM, 0:N(1), 0:N(2))
         real(kind=RP),    intent(out) :: F   (1:nEqn, 1:NDIM, 0:N(1), 0:N(2))
!
!        ---------------
!        Local variables
!        ---------------
!
         real(kind=RP) :: T, sutherLaw
         real(kind=RP) :: divV
         real(kind=RP) :: u(NDIM)
         integer       :: i , j , k
         real(kind=RP) :: invRho, uDivRho(NDIM), u_x(NDIM), u_y(NDIM), u_z(NDIM), nablaT(NDIM)
         
         associate( gammaM2 => dimensionless % gammaM2, &
                    gammaMinus1 => thermodynamics % gammaMinus1 ) 

         do j = 0, N(2) ; do i = 0, N(1)
!
!           Compute the density inverse and velocities
!           ------------------------------------------
            invRho  = 1.0_RP / Q(IRHO,i,j)
            u       = Q(IRHOU:IRHOW,i,j) * invRho
            uDivRho = u * invRho
   
            T = gammaM2 * gammaMinus1 * ( invRho * Q(IRHOE,i,j) - 0.5_RP * ( u(IX) * u(IX) + u(IY) * u(IY) + u(IZ) * u(IZ) ) )
            sutherLaw = SutherlandsLaw(T)
            
            u_x = invRho * Q_x(IRHOU:IRHOW,i,j) - uDivRho * Q_x(IRHO,i,j)
            u_y = invRho * Q_y(IRHOU:IRHOW,i,j) - uDivRho * Q_y(IRHO,i,j)
            u_z = invRho * Q_z(IRHOU:IRHOW,i,j) - uDivRho * Q_z(IRHO,i,j)
   
            nablaT(IX) =  gammaMinus1* gammaM2*(invRho*Q_x(IRHOE,i,j) - Q(IRHOE,i,j)*invRho*invRho*Q_x(IRHO,i,j) - u(IX)*u_x(IX)-u(IY)*u_x(IY)-u(IZ)*u_x(IZ))
            nablaT(IY) =  gammaMinus1* gammaM2*(invRho*Q_y(IRHOE,i,j) - Q(IRHOE,i,j)*invRho*invRho*Q_y(IRHO,i,j) - u(IX)*u_y(IX)-u(IY)*u_y(IY)-u(IZ)*u_y(IZ))
            nablaT(IZ) =  gammaMinus1* gammaM2*(invRho*Q_z(IRHOE,i,j) - Q(IRHOE,i,j)*invRho*invRho*Q_z(IRHO,i,j) - u(IX)*u_z(IX)-u(IY)*u_z(IY)-u(IZ)*u_z(IZ))

            divV = U_x(IX) + U_y(IY) + U_z(IZ)
   
            F(IRHO ,IX,i,j) = 0.0_RP
            F(IRHOU,IX,i,j) = mu(i,j) * sutherLaw * (2.0_RP * U_x(IX) - 2.0_RP/3.0_RP * divV ) - tauSGS(1,1,i,j)
            F(IRHOV,IX,i,j) = mu(i,j) * sutherLaw * ( U_x(IY) + U_y(IX) ) - tauSGS(2,1,i,j)
            F(IRHOW,IX,i,j) = mu(i,j) * sutherLaw * ( U_x(IZ) + U_z(IX) ) - tauSGS(3,1,i,j)
            F(IRHOE,IX,i,j) = F(IRHOU,IX,i,j) * u(IX) + F(IRHOV,IX,i,j) * u(IY) + F(IRHOW,IX,i,j) * u(IZ) &
                  + sutherLaw * kappa(i,j) * nablaT(IX) - qSGS(1,i,j)
   
            F(IRHO, IY,i,j) = 0.0_RP
            F(IRHOU,IY,i,j) = mu(i,j) * sutherLaw * ( U_x(IY) + U_y(IX) )  - tauSGS(1,2,i,j)
            F(IRHOV,IY,i,j) = mu(i,j) * sutherLaw * (2.0_RP * U_y(IY) - 2.0_RP / 3.0_RP * divV ) - tauSGS(2,2,i,j)
            F(IRHOW,IY,i,j) = mu(i,j) * sutherLaw * ( U_y(IZ) + U_z(IY) ) - tauSGS(3,2,i,j)
            F(IRHOE,IY,i,j) = F(IRHOU,IY,i,j) * u(IX) + F(IRHOV,IY,i,j) * u(IY) + F(IRHOW,IY,i,j) * u(IZ) &
                  + sutherLaw * kappa(i,j) * nablaT(IY) - qSGS(2,i,j)
   
            F(IRHO, IZ,i,j ) = 0.0_RP
            F(IRHOU,IZ,i,j) = mu(i,j) * sutherLaw * ( U_x(IZ) + U_z(IX) ) - tauSGS(1,3,i,j)
            F(IRHOV,IZ,i,j) = mu(i,j) * sutherLaw * ( U_y(IZ) + U_z(IY) ) - tauSGS(2,3,i,j)
            F(IRHOW,IZ,i,j) = mu(i,j) * sutherLaw * ( 2.0_RP * U_z(IZ) - 2.0_RP / 3.0_RP * divV ) - tauSGS(3,3,i,j)
            F(IRHOE,IZ,i,j) = F(IRHOU,IZ,i,j) * u(IX) + F(IRHOV,IZ,i,j) * u(IY) + F(IRHOW,IZ,i,j) * u(IZ) &
                  + sutherLaw * kappa(i,j) * nablaT(IZ) - qSGS(3,i,j)
   
         end do    ; end do

         end associate

      end subroutine ViscousFlux2D_withSGS

      pure subroutine ViscousFlux3D_withSGS(nEqn, nGradEqn, N, Q, Q_x, Q_y, Q_z, mu, kappa, tauSGS, qSGS, F)
         implicit none
         integer,          intent(in)  :: nEqn
         integer,          intent(in)  :: nGradEqn
         integer         , intent(in)  :: N(3)
         real(kind=RP),    intent(in)  :: Q  (1:nEqn, 0:N(1), 0:N(2), 0:N(3))
         real(kind=RP),    intent(in)  :: Q_x(1:nGradEqn, 0:N(1), 0:N(2), 0:N(3) )
         real(kind=RP),    intent(in)  :: Q_y(1:nGradEqn, 0:N(1), 0:N(2), 0:N(3) )
         real(kind=RP),    intent(in)  :: Q_z(1:nGradEqn, 0:N(1), 0:N(2), 0:N(3) )
         real(kind=RP),    intent(in)  :: mu  (0:N(1), 0:N(2), 0:N(3))
         real(kind=RP),    intent(in)  :: kappa(0:N(1), 0:N(2), 0:N(3))
         real(kind=RP),    intent(in)  :: tauSGS(1:NDIM, 1:NDIM, 0:N(1), 0:N(2), 0:N(3))
         real(kind=RP),    intent(in)  :: qSGS(1:NDIM, 0:N(1), 0:N(2), 0:N(3))
         real(kind=RP),    intent(out) :: F   (1:nEqn, 0:N(1), 0:N(2), 0:N(3), 1:NDIM )
!
!        ---------------
!        Local variables
!        ---------------
!
         real(kind=RP) :: invRho, uDivRho(NDIM), u_x(NDIM), u_y(NDIM), u_z(NDIM), nablaT(NDIM)
         real(kind=RP) :: T, sutherLaw
         real(kind=RP) :: divV
         real(kind=RP) :: u(NDIM)
         integer       :: i , j , k

         associate( gammaM2 => dimensionless % gammaM2, &
                    gammaMinus1 => thermodynamics % gammaMinus1 ) 

         do k = 0, N(3) ; do j = 0, N(2) ; do i = 0, N(1)
!
!           Compute the density inverse and velocities
!           ------------------------------------------
            invRho  = 1.0_RP / Q(IRHO,i,j,k)
            u       = Q(IRHOU:IRHOW,i,j,k) * invRho
            uDivRho = u * invRho
   
            T = gammaM2 * gammaMinus1 * ( invRho * Q(IRHOE,i,j,k) - 0.5_RP * ( u(IX) * u(IX) + u(IY) * u(IY) + u(IZ) * u(IZ) ) )
            sutherLaw = SutherlandsLaw(T)
            
            u_x = invRho * Q_x(IRHOU:IRHOW,i,j,k) - uDivRho * Q_x(IRHO,i,j,k)
            u_y = invRho * Q_y(IRHOU:IRHOW,i,j,k) - uDivRho * Q_y(IRHO,i,j,k)
            u_z = invRho * Q_z(IRHOU:IRHOW,i,j,k) - uDivRho * Q_z(IRHO,i,j,k)
   
            nablaT(IX) =  gammaMinus1* gammaM2*(invRho*Q_x(IRHOE,i,j,k) - Q(IRHOE,i,j,k)*invRho*invRho*Q_x(IRHO,i,j,k) - u(IX)*u_x(IX)-u(IY)*u_x(IY)-u(IZ)*u_x(IZ))
            nablaT(IY) =  gammaMinus1* gammaM2*(invRho*Q_y(IRHOE,i,j,k) - Q(IRHOE,i,j,k)*invRho*invRho*Q_y(IRHO,i,j,k) - u(IX)*u_y(IX)-u(IY)*u_y(IY)-u(IZ)*u_y(IZ))
            nablaT(IZ) =  gammaMinus1* gammaM2*(invRho*Q_z(IRHOE,i,j,k) - Q(IRHOE,i,j,k)*invRho*invRho*Q_z(IRHO,i,j,k) - u(IX)*u_z(IX)-u(IY)*u_z(IY)-u(IZ)*u_z(IZ))
            
            divV = U_x(IX) + U_y(IY) + U_z(IZ)
!
!           Compute the fluxes
!           ------------------
   
            F(IRHO,i,j,k ,IX) = 0.0_RP
            F(IRHOU,i,j,k,IX) = mu(i,j,k) * sutherLaw * (2.0_RP * U_x(IX) - 2.0_RP/3.0_RP * divV ) - tauSGS(1,1,i,j,k)
            F(IRHOV,i,j,k,IX) = mu(i,j,k) * sutherLaw * ( U_x(IY) + U_y(IX) ) - tauSGS(2,1,i,j,k)
            F(IRHOW,i,j,k,IX) = mu(i,j,k) * sutherLaw * ( U_x(IZ) + U_z(IX) ) - tauSGS(3,1,i,j,k)
            F(IRHOE,i,j,k,IX) = F(IRHOU,i,j,k,IX) * u(IX) + F(IRHOV,i,j,k,IX) * u(IY) + F(IRHOW,i,j,k,IX) * u(IZ) &
                  + sutherLaw * kappa(i,j,k) * nablaT(IX) - qSGS(1,i,j,k)
                  
            F(IRHO,i,j,k ,IY) = 0.0_RP
            F(IRHOU,i,j,k,IY) = mu(i,j,k) * sutherLaw * ( U_x(IY) + U_y(IX) )  - tauSGS(1,2,i,j,k)
            F(IRHOV,i,j,k,IY) = mu(i,j,k) * sutherLaw * (2.0_RP * U_y(IY) - 2.0_RP / 3.0_RP * divV ) - tauSGS(2,2,i,j,k)
            F(IRHOW,i,j,k,IY) = mu(i,j,k) * sutherLaw * ( U_y(IZ) + U_z(IY) ) - tauSGS(3,2,i,j,k)
            F(IRHOE,i,j,k,IY) = F(IRHOU,i,j,k,IY) * u(IX) + F(IRHOV,i,j,k,IY) * u(IY) + F(IRHOW,i,j,k,IY) * u(IZ) &
                  + sutherLaw * kappa(i,j,k) * nablaT(IY) - qSGS(2,i,j,k)
                  
            F(IRHO,i,j,k,IZ ) = 0.0_RP
            F(IRHOU,i,j,k,IZ) = mu(i,j,k) * sutherLaw * ( U_x(IZ) + U_z(IX) ) - tauSGS(1,3,i,j,k)
            F(IRHOV,i,j,k,IZ) = mu(i,j,k) * sutherLaw * ( U_y(IZ) + U_z(IY) ) - tauSGS(2,3,i,j,k)
            F(IRHOW,i,j,k,IZ) = mu(i,j,k) * sutherLaw * ( 2.0_RP * U_z(IZ) - 2.0_RP / 3.0_RP * divV ) - tauSGS(3,3,i,j,k)
            F(IRHOE,i,j,k,IZ) = F(IRHOU,i,j,k,IZ) * u(IX) + F(IRHOV,i,j,k,IZ) * u(IY) + F(IRHOW,i,j,k,IZ) * u(IZ) &
                  + sutherLaw * kappa(i,j,k) * nablaT(IZ) - qSGS(3,i,j,k)
   
         end do      ; end do    ; end do

         end associate

      end subroutine ViscousFlux3D_withSGS

!
!---------------------------------------------------------------------
!! Compute the molecular diffusivity by way of Sutherland's law
!---------------------------------------------------------------------
!
      PURE FUNCTION SutherlandsLaw(T) RESULT(mu)
!
!     ---------
!     Arguments
!     ---------
!
      REAL(KIND=RP), INTENT(IN) :: T !! The temperature
!
!     ---------------
!     Local Variables
!     ---------------
!
      REAL(KIND=RP) :: mu !! The diffusivity
      real(kind=RP) :: tildeT

      tildeT = T*TemperatureReNormalization_Sutherland
!      
      mu = (1._RP + S_div_TRef_Sutherland)/(tildeT + S_div_TRef_Sutherland)*tildeT*SQRT(tildeT)


      END FUNCTION SutherlandsLaw
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
      pure function SutherlandsLawDeriv(Q,T) result(dMu_dQ)
         implicit none
         !-arguments--------------------------------
         real(kind=RP), intent(in) :: Q(NCONS)
         real(kind=RP), intent(in) :: T
         real(kind=RP)             :: dMu_dQ(NCONS)
         !------------------------------------------
         
         dMu_dQ = (1._RP + S_div_TRef_Sutherland)/(T + S_div_TRef_Sutherland) * sqrt(T) * (1.5_RP - T/(T + S_div_TRef_Sutherland)) * TemperatureDeriv(Q)
         
      end function SutherlandsLawDeriv
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
      pure subroutine getStressTensor(Q,Q_x,Q_y,Q_z,tau)
         implicit none
         real(kind=RP), intent(in)      :: Q   (1:NCONS         )
         real(kind=RP), intent(in)      :: Q_x (1:NGRAD    )
         real(kind=RP), intent(in)      :: Q_y (1:NGRAD    )
         real(kind=RP), intent(in)      :: Q_z (1:NGRAD    )
         real(kind=RP), intent(out)     :: tau (1:NDIM, 1:NDIM   )
!
!        ---------------
!        Local variables
!        ---------------
!
         real(kind=RP) :: T , muOfT
         real(kind=RP) :: divV
         real(kind=RP) :: U_x(NDIM), U_y(NDIM), U_z(NDIM), invRho, invRho2, uDivRho(NDIM)

         associate ( mu0 => dimensionless % mu )
         
         invRho  = 1._RP / Q(IRHO)
         invRho2 = invRho * invRho
         
         uDivRho = [Q(IRHOU) , Q(IRHOV) , Q(IRHOW) ] * invRho2
         
         u_x = invRho * Q_x(IRHOU:IRHOW) - uDivRho * Q_x(IRHO)
         u_y = invRho * Q_y(IRHOU:IRHOW) - uDivRho * Q_y(IRHO)
         u_z = invRho * Q_z(IRHOU:IRHOW) - uDivRho * Q_z(IRHO)
         
         T     = Temperature(Q)
         muOfT = SutherlandsLaw(T)

         divV = U_x(IX) + U_y(IY) + U_z(IZ)

         tau(IX,IX) = mu0 * muOfT * (2.0_RP * U_x(IX) - 2.0_RP/3.0_RP * divV )
         tau(IY,IX) = mu0 * muOfT * ( U_x(IY) + U_y(IX) ) 
         tau(IZ,IX) = mu0 * muOfT * ( U_x(IZ) + U_z(IX) ) 
         tau(IX,IY) = tau(IY,IX)
         tau(IY,IY) = mu0 * muOfT * (2.0_RP * U_y(IY) - 2.0_RP/3.0_RP * divV )
         tau(IZ,IY) = mu0 * muOfT * ( U_y(IZ) + U_z(IY) ) 
         tau(IX,IZ) = tau(IZ,IX)
         tau(IY,IZ) = tau(IZ,IY)
         tau(IZ,IZ) = mu0 * muOfT * (2.0_RP * U_z(IZ) - 2.0_RP/3.0_RP * divV )

         end associate

      end subroutine getStressTensor
   END Module Physics_NS
!@mark -
!
! /////////////////////////////////////////////////////////////////////
!
!----------------------------------------------------------------------
!! This routine returns the maximum eigenvalues for the Euler equations 
!! for the given solution value in each spatial direction. 
!! These are to be used to compute the local time step.
!----------------------------------------------------------------------
!
      SUBROUTINE ComputeEigenvaluesForState( Q, eigen )
      
      USE SMConstants
      USE PhysicsStorage_NS
      USE VariableConversion_NS, ONLY:Pressure
      use FluidData_NS,          only: Thermodynamics
      IMPLICIT NONE
!
!     ---------
!     Arguments
!     ---------
!
      REAL(KIND=Rp), DIMENSION(NCONS) :: Q
      REAL(KIND=Rp), DIMENSION(3)     :: eigen
!
!     ---------------
!     Local Variables
!     ---------------
!
      REAL(KIND=Rp) :: u, v, w, p, a
!      
      associate ( gamma => thermodynamics % gamma ) 

      u = ABS( Q(2)/Q(1) )
      v = ABS( Q(3)/Q(1) )
      w = ABS( Q(4)/Q(1) )
      p = Pressure(Q)
      a = SQRT(gamma*p/Q(1))
      
      eigen(1) = u + a
      eigen(2) = v + a
      eigen(3) = w + a

      end associate
      
      END SUBROUTINE ComputeEigenvaluesForState
