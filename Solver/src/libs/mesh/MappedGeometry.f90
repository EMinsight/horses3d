!
!////////////////////////////////////////////////////////////////////////
!
!      MappedGeometry.f95
!      Created: 2008-06-19 15:58:02 -0400 
!      By: David Kopriva  
!
!      Modification history:
!        2008-06-19: Created by David Kopriva
!        XXXX-XX-XX: Gonzalo Rubio implemented cross-product metrics
!        2017-05-05: Andrés Rueda implemented polynomial anisotropy
!        2017-05-23: Juan Manzanero implemented invatiant metrics and
!                    face geometry construction
!      Contains:
!         ALGORITHM 101: MappedGeometryClass
!         ALGORITHM 102: ConstructMappedGeometry
!
!////////////////////////////////////////////////////////////////////////
!
Module MappedGeometryClass 
   USE SMConstants
   USE TransfiniteMapClass
   USE NodalStorageClass
   use MeshTypes
   IMPLICIT NONE
!
!     ---------
!     Constants
!     ---------
!
      integer, parameter :: EFRONT = 1, EBACK = 2, EBOTTOM = 3
      integer, parameter :: ERIGHT = 4, ETOP = 5, ELEFT = 6

      LOGICAL       :: useCrossProductMetrics = .false.
!
!     -----
!     Class
!     -----
!
      TYPE MappedGeometry
            INTEGER                                         :: Nx, Ny, Nz                    ! Polynomial order
            REAL(KIND=RP), DIMENSION(:,:,:,:) , ALLOCATABLE :: jGradXi, jGradEta, jGradZeta  ! 
            REAL(KIND=RP), DIMENSION(:,:,:,:) , ALLOCATABLE :: x                             ! Position of points in absolute coordinates
            REAL(KIND=RP), DIMENSION(:,:,:)   , ALLOCATABLE :: jacobian 
            
            CONTAINS
            
            PROCEDURE :: construct => ConstructMappedGeometry
            PROCEDURE :: destruct  => DestructMappedGeometry
      END TYPE MappedGeometry
      
      type MappedGeometryFace
         real(kind=RP), dimension(:,:,:),   allocatable :: x
         real(kind=RP), dimension(:,:)  , allocatable   :: scal   ! |ja^i|: Normalization term of the normal vectors on a face
         real(kind=RP), dimension(:,:,:), allocatable   :: normal ! normal vector on a face
         contains
            procedure :: construct => ConstructMappedGeometryFace
            procedure :: destruct  => DestructMappedGeometryFace
      end type MappedGeometryFace
      
!
!  ========
   CONTAINS 
!  ========
!
!////////////////////////////////////////////////////////////////////////
!
   SUBROUTINE ConstructMappedGeometry( self, spAxi, spAeta, spAzeta, mapper )
      IMPLICIT NONE
!
!      ---------
!      Arguments
!      ---------
!
      CLASS(MappedGeometry)  , intent(inout) :: self
      TYPE(TransfiniteHexMap), intent(in)    :: mapper
      TYPE(NodalStorage)     , intent(in)    :: spAxi
      TYPE(NodalStorage)     , intent(in)    :: spAeta
      TYPE(NodalStorage)     , intent(in)    :: spAzeta
!
!     ---------------
!     Local Variables
!     ---------------
!
      INTEGER       :: Nx, Ny, Nz, Nmax
      INTEGER       :: i, j, k
      REAL(KIND=RP) :: nrm
      REAL(KIND=RP) :: grad_x(3,3), jGrad(3)
!
!     -----------
!     Allocations
!     -----------
!
      Nx        = spAxi   % N
      Ny        = spAeta  % N
      Nz        = spAzeta % N
      Nmax      = MAX(Nx,Ny,Nz)
      self % Nx = Nx
      self % Ny = Ny
      self % Nz = Nz
      
      ALLOCATE( self % JGradXi  (3,0:Nx,0:Ny,0:Nz) )
      ALLOCATE( self % JGradEta (3,0:Nx,0:Ny,0:Nz) )
      ALLOCATE( self % JGradZeta(3,0:Nx,0:Ny,0:Nz) )
      ALLOCATE( self % jacobian   (0:Nx,0:Ny,0:Nz) )
      ALLOCATE( self % x        (3,0:Nx,0:Ny,0:Nz)    )
!
!     --------------------------
!     Compute interior locations
!     --------------------------
!
      DO k = 0, Nz
         DO j= 0, Ny       
            DO i = 0,Nx 
               self % x(:,i,j,k) = mapper %  transfiniteMapAt([spAxi % x(i), spAeta % x(j), spAzeta % x(k)])
            END DO
         END DO
      END DO
!
!     ------------
!     Metric terms
!     ------------
!
      IF ( useCrossProductMetrics ) THEN 
      
         CALL computeMetricTermsCrossProductForm(self, spAxi, spAeta, spAzeta, mapper)
         
      ELSE
         
         CALL computeMetricTermsConservativeForm(self, spAxi, spAeta, spAzeta, mapper)
      
      ENDIF
      
   END SUBROUTINE ConstructMappedGeometry
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE DestructMappedGeometry(self)
         IMPLICIT NONE 
         CLASS(MappedGeometry) :: self
         DEALLOCATE( self % jGradXi, self % jGradEta, self % jGradZeta, self % jacobian )
         DEALLOCATE( self % x)
      END SUBROUTINE DestructMappedGeometry
!
!////////////////////////////////////////////////////////////////////////
!
      subroutine computeMetricTermsConservativeForm(self, spAxi, spAeta, spAzeta, mapper)
!
!        *********************************************************************
!              Currently, the invariant form is implemented
!
!              Ja^i_n = -1/2 \hat{x}^i ( Xl \nabla Xm - Xm \nabla Xl ) 
!                 (i,j,k) and (n,m,l) cyclic
!        *********************************************************************
!
         use PhysicsStorage
         implicit none
         type(MappedGeometry),    intent(inout) :: self
         type(NodalStorage),      intent(in)    :: spAxi, spAeta, spAzeta
         type(TransfiniteHexMap), intent(in)    :: mapper
!
!        ---------------
!        Local variables
!        ---------------
!
         integer     :: i, j, k, m, n, l
         real(kind=RP)  :: grad_x(NDIM,NDIM,0:self % Nx, 0:self % Ny, 0:self % Nz)
         real(kind=RP)  :: xCGL(NDIM,0:self % Nx, 0:self % Ny, 0:self % Nz)
         real(kind=RP)  :: auxgrad(NDIM,NDIM,0:self % Nx, 0:self % Ny, 0:self % Nz)
         real(kind=RP)  :: coordsProduct(NDIM,0:self % Nx,0:self % Ny,0:self % Nz)
         real(kind=RP)  :: Jai(NDIM,0:self % Nx, 0:self % Ny, 0:self % Nz)
         real(kind=RP)  :: Ja1CGL(NDIM,0:self % Nx, 0:self % Ny, 0:self % Nz)
         real(kind=RP)  :: Ja2CGL(NDIM,0:self % Nx, 0:self % Ny, 0:self % Nz)
         real(kind=RP)  :: Ja3CGL(NDIM,0:self % Nx, 0:self % Ny, 0:self % Nz)
         real(kind=RP)  :: JacobianCGL(0:self % Nx, 0:self % Ny, 0:self % Nz)
!
!        Compute the mapping gradient in Chebyshev-Gauss-Lobatto points
!        --------------------------------------------------------------
         do k = 0, self % Nz ; do j = 0, self % Ny  ; do i = 0, self % Nx
            xCGL(:,i,j,k) = mapper % transfiniteMapAt([spAxi % xCGL(i), spAeta % xCGL(j), &
                                                       spAzeta % xCGL(k)])
            grad_x(:,:,i,j,k) = mapper % metricDerivativesAt([spAxi % xCGL(i), spAeta % xCGL(j), &
                                                              spAzeta % xCGL(k)])
         end do         ; end do          ; end do
!
!        *****************************************
!        Compute the x-coordinates of the mappings
!        *****************************************
!
!        Compute coordinates combination
!        -------------------------------
         do k = 0, self % Nz    ; do j = 0, self % Ny  ; do i = 0, self % Nx
            coordsProduct(:,i,j,k) =   xCGL(3,i,j,k) * grad_x(2,:,i,j,k)  &
                                     - xCGL(2,i,j,k) * grad_x(3,:,i,j,k)
         end do            ; end do          ; end do
!
!        Compute its gradient
!        --------------------
         auxgrad = 0.0_RP
         do k = 0, self % Nz ; do j = 0, self % Ny  ; do i = 0, self % Nx
            do l = 0, self % Nx
               auxgrad(:,1,i,j,k) = auxgrad(:,1,i,j,k) + coordsProduct(:,l,j,k) * spAxi % DCGL(i,l)
            end do
      
            do l = 0, self % Ny
               auxgrad(:,2,i,j,k) = auxgrad(:,2,i,j,k) + coordsProduct(:,i,l,k) * spAeta % DCGL(j,l)
            end do

            do l = 0, self % Nz
               auxgrad(:,3,i,j,k) = auxgrad(:,3,i,j,k) + coordsProduct(:,i,j,l) * spAzeta % DCGL(k,l)
            end do
         end do         ; end do          ; end do
!
!        Compute the curl
!        ----------------
         do k = 0, self % Nz ; do j = 0, self % Ny  ; do i = 0, self % Nx
            Jai(1,i,j,k) = auxgrad(3,2,i,j,k) - auxgrad(2,3,i,j,k)
            Jai(2,i,j,k) = auxgrad(1,3,i,j,k) - auxgrad(3,1,i,j,k)
            Jai(3,i,j,k) = auxgrad(2,1,i,j,k) - auxgrad(1,2,i,j,k)
         end do         ; end do          ; end do
!
!        Assign to the first coordinate of each metrics
!        ----------------------------------------------
         Ja1CGL(1,:,:,:)  = -0.5_RP * Jai(1,:,:,:)
         Ja2CGL(1,:,:,:)  = -0.5_RP * Jai(2,:,:,:)
         Ja3CGL(1,:,:,:)  = -0.5_RP * Jai(3,:,:,:)
!
!        *****************************************
!        Compute the y-coordinates of the mappings
!        *****************************************
!
!        Compute coordinates combination
!        -------------------------------
         do k = 0, self % Nz    ; do j = 0, self % Ny  ; do i = 0, self % Nx
            coordsProduct(:,i,j,k) =   xCGL(1,i,j,k) * grad_x(3,:,i,j,k) &
                                     - xCGL(3,i,j,k) * grad_x(1,:,i,j,k)
         end do            ; end do          ; end do
!
!        Compute its gradient
!        --------------------
         auxgrad = 0.0_RP
         do k = 0, self % Nz ; do j = 0, self % Ny  ; do i = 0, self % Nx
            do l = 0, self % Nx
               auxgrad(:,1,i,j,k) = auxgrad(:,1,i,j,k) + coordsProduct(:,l,j,k) * spAxi % DCGL(i,l)
            end do
      
            do l = 0, self % Ny
               auxgrad(:,2,i,j,k) = auxgrad(:,2,i,j,k) + coordsProduct(:,i,l,k) * spAeta % DCGL(j,l)
            end do

            do l = 0, self % Nz
               auxgrad(:,3,i,j,k) = auxgrad(:,3,i,j,k) + coordsProduct(:,i,j,l) * spAzeta % DCGL(k,l)
            end do
         end do         ; end do          ; end do
!
!        Compute the curl
!        ----------------
         do k = 0, self % Nz ; do j = 0, self % Ny  ; do i = 0, self % Nx
            Jai(1,i,j,k) = auxgrad(3,2,i,j,k) - auxgrad(2,3,i,j,k)
            Jai(2,i,j,k) = auxgrad(1,3,i,j,k) - auxgrad(3,1,i,j,k)
            Jai(3,i,j,k) = auxgrad(2,1,i,j,k) - auxgrad(1,2,i,j,k)
         end do         ; end do          ; end do
!
!        Assign to the second coordinate of each metrics
!        -----------------------------------------------
         Ja1CGL(2,:,:,:)  = -0.5_RP*Jai(1,:,:,:)
         Ja2CGL(2,:,:,:)  = -0.5_RP*Jai(2,:,:,:)
         Ja3CGL(2,:,:,:)  = -0.5_RP*Jai(3,:,:,:)
!
!        *****************************************
!        Compute the z-coordinates of the mappings
!        *****************************************
!
!        Compute coordinates combination
!        -------------------------------
         do k = 0, self % Nz    ; do j = 0, self % Ny  ; do i = 0, self % Nx
            coordsProduct(:,i,j,k) =   xCGL(2,i,j,k) * grad_x(1,:,i,j,k) &
                                     - xCGL(1,i,j,k) * grad_x(2,:,i,j,k)
         end do            ; end do          ; end do
!
!        Compute its gradient
!        --------------------
         auxgrad = 0.0_RP
         do k = 0, self % Nz ; do j = 0, self % Ny  ; do i = 0, self % Nx
            do l = 0, self % Nx
               auxgrad(:,1,i,j,k) = auxgrad(:,1,i,j,k) + coordsProduct(:,l,j,k) * spAxi % DCGL(i,l)
            end do
      
            do l = 0, self % Ny
               auxgrad(:,2,i,j,k) = auxgrad(:,2,i,j,k) + coordsProduct(:,i,l,k) * spAeta % DCGL(j,l)
            end do

            do l = 0, self % Nz
               auxgrad(:,3,i,j,k) = auxgrad(:,3,i,j,k) + coordsProduct(:,i,j,l) * spAzeta % DCGL(k,l)
            end do
         end do         ; end do          ; end do
!
!        Compute the curl
!        ----------------
         do k = 0, self % Nz ; do j = 0, self % Ny  ; do i = 0, self % Nx
            Jai(1,i,j,k) = auxgrad(3,2,i,j,k) - auxgrad(2,3,i,j,k)
            Jai(2,i,j,k) = auxgrad(1,3,i,j,k) - auxgrad(3,1,i,j,k)
            Jai(3,i,j,k) = auxgrad(2,1,i,j,k) - auxgrad(1,2,i,j,k)
         end do         ; end do          ; end do
!
!        Assign to the third coordinate of each metrics
!        ----------------------------------------------
         Ja1CGL(3,:,:,:)  = -0.5_RP * Jai(1,:,:,:)
         Ja2CGL(3,:,:,:)  = -0.5_RP * Jai(2,:,:,:)
         Ja3CGL(3,:,:,:)  = -0.5_RP * Jai(3,:,:,:)
!
!        ********************
!        Compute the Jacobian
!        ********************
!
         do k = 0, self % Nz  ; do j = 0, self % Ny   ; do i = 0, self % Nx
            JacobianCGL(i,j,k) = jacobian3D(a1 = grad_x(:,1,i,j,k), &
                                                a2 = grad_x(:,2,i,j,k), &
                                                a3 = grad_x(:,3,i,j,k)   )
         end do               ; end do                ; end do
!
!        **********************
!        Return to Gauss points
!        **********************
!
         self % jGradXi = 0.0_RP
         self % jGradEta = 0.0_RP
         self % jGradZeta = 0.0_RP
         self % jacobian = 0.0_RP

         do k = 0, self % Nz  ; do j = 0, self % Ny  ; do i = 0, self % Nx
            do n = 0, self % Nz ; do m = 0, self % Ny ; do l = 0, self % Nx
               self % jGradXi(:,i,j,k) = self % jGradXi(:,i,j,k) + Ja1CGL(:,l,m,n) &
                                          * spAxi % TCheb2Gauss(i,l) &
                                          * spAeta % TCheb2Gauss(j,m) &
                                          * spAzeta % TCheb2Gauss(k,n) 

               self % jGradEta(:,i,j,k) = self % jGradEta(:,i,j,k) + Ja2CGL(:,l,m,n) &
                                          * spAxi % TCheb2Gauss(i,l) &
                                          * spAeta % TCheb2Gauss(j,m) &
                                          * spAzeta % TCheb2Gauss(k,n) 

               self % jGradZeta(:,i,j,k) = self % jGradZeta(:,i,j,k) + Ja3CGL(:,l,m,n) &
                                          * spAxi % TCheb2Gauss(i,l) &
                                          * spAeta % TCheb2Gauss(j,m) &
                                          * spAzeta % TCheb2Gauss(k,n) 

               self % jacobian(i,j,k) = self % jacobian(i,j,k) + JacobianCGL(l,m,n) &
                                          * spAxi % TCheb2Gauss(i,l) &
                                          * spAeta % TCheb2Gauss(j,m) &
                                          * spAzeta % TCheb2Gauss(k,n) 
            end do              ; end do              ; end do
         end do               ; end do               ; end do

      end subroutine computeMetricTermsConservativeForm
!
!///////////////////////////////////////////////////////////////////////
!
      SUBROUTINE computeMetricTermsCrossProductForm(self, spAxi, spAeta, spAzeta, mapper)       
!
!     -----------------------------------------------
!     Compute the metric terms in cross product form 
!     -----------------------------------------------
!
         use PhysicsStorage
         IMPLICIT NONE  
!
!        ---------
!        Arguments
!        ---------
!
         TYPE(MappedGeometry)   , intent(inout) :: self
         TYPE(NodalStorage)     , intent(in)    :: spAxi
         TYPE(NodalStorage)     , intent(in)    :: spAeta
         TYPE(NodalStorage)     , intent(in)    :: spAzeta
         TYPE(TransfiniteHexMap), intent(in)    :: mapper
!
!        ---------------
!        Local Variables
!        ---------------
!
         INTEGER       :: i,j,k,l,m,n
         INTEGER       :: Nx, Ny, Nz
         REAL(KIND=RP) :: grad_x(3,3)         
         real(kind=RP)  :: Ja1CGL(NDIM,0:self % Nx, 0:self % Ny, 0:self % Nz)
         real(kind=RP)  :: Ja2CGL(NDIM,0:self % Nx, 0:self % Ny, 0:self % Nz)
         real(kind=RP)  :: Ja3CGL(NDIM,0:self % Nx, 0:self % Ny, 0:self % Nz)
         real(kind=RP)  :: JacobianCGL(0:self % Nx, 0:self % Ny, 0:self % Nz)

         Nx = spAxi % N
         Ny = spAeta % N
         Nz = spAzeta % N
         
         DO k = 0, Nz
            DO j = 0,Ny
               DO i = 0,Nx
                  grad_x = mapper % metricDerivativesAt([spAxi % xCGL(i), spAeta % xCGL(j), &
                                                              spAzeta % xCGL(k)])
                 
                  CALL vCross( grad_x(:,2), grad_x(:,3), Ja1CGL (:,i,j,k))
                  CALL vCross( grad_x(:,3), grad_x(:,1), Ja2CGL (:,i,j,k))
                  CALL vCross( grad_x(:,1), grad_x(:,2), Ja3CGL(:,i,j,k))

                  JacobianCGL(i,j,k) = jacobian3D(a1 = grad_x(:,1),a2 = grad_x(:,2),a3 = grad_x(:,3))
               END DO   
            END DO   
         END DO  
!
!        **********************
!        Return to Gauss points
!        **********************
!
         self % jGradXi = 0.0_RP
         self % jGradEta = 0.0_RP
         self % jGradZeta = 0.0_RP
         self % jacobian = 0.0_RP

         do k = 0, self % Nz  ; do j = 0, self % Ny  ; do i = 0, self % Nx
            do n = 0, self % Nz ; do m = 0, self % Ny ; do l = 0, self % Nx
               self % jGradXi(:,i,j,k) = self % jGradXi(:,i,j,k) + Ja1CGL(:,l,m,n) &
                                          * spAxi % TCheb2Gauss(i,l) &
                                          * spAeta % TCheb2Gauss(j,m) &
                                          * spAzeta % TCheb2Gauss(k,n) 

               self % jGradEta(:,i,j,k) = self % jGradEta(:,i,j,k) + Ja2CGL(:,l,m,n) &
                                          * spAxi % TCheb2Gauss(i,l) &
                                          * spAeta % TCheb2Gauss(j,m) &
                                          * spAzeta % TCheb2Gauss(k,n) 

               self % jGradZeta(:,i,j,k) = self % jGradZeta(:,i,j,k) + Ja3CGL(:,l,m,n) &
                                          * spAxi % TCheb2Gauss(i,l) &
                                          * spAeta % TCheb2Gauss(j,m) &
                                          * spAzeta % TCheb2Gauss(k,n) 

               self % jacobian(i,j,k) = self % jacobian(i,j,k) + JacobianCGL(l,m,n) &
                                          * spAxi % TCheb2Gauss(i,l) &
                                          * spAeta % TCheb2Gauss(j,m) &
                                          * spAzeta % TCheb2Gauss(k,n) 
            end do              ; end do              ; end do
         end do               ; end do               ; end do



      END SUBROUTINE computeMetricTermsCrossProductForm
!
!//////////////////////////////////////////////////////////////////////// 
!
!  -----------------------------------------------------------------------------------
!  Computation of the metric terms on a face: TODO only the Left element (rotation 0)
!  -----------------------------------------------------------------------------------
   subroutine ConstructMappedGeometryFace(self, Nf, Nelf, Nel, Nel3D, spAf, spAe, geom, hexMap, side, projType, eSide, rot)
      use PhysicsStorage
      use PolynomialInterpAndDerivsModule
      implicit none
      class(MappedGeometryFace), intent(inout)  :: self
      integer,                   intent(in)     :: Nf(2)    ! Face polynomial order
      integer,                   intent(in)     :: Nelf(2)  ! Element face pOrder (with rotation)
      integer,                   intent(in)     :: Nel(2)   ! Element face pOrder (without rotation)
      integer,                   intent(in)     :: Nel3D(3) ! Element pOrder
      type(NodalStorage),        intent(in)     :: spAf(2)
      type(NodalStorage),        intent(in)     :: spAe(3)
      type(MappedGeometry),      intent(in)     :: geom
      type(TransfiniteHexMap),   intent(in)     :: hexMap
      integer,                   intent(in)     :: side
      integer,                   intent(in)     :: projType
      integer,                   intent(in)     :: eSide
      integer,                   intent(in)     :: rot
!
!     ---------------
!     Local variables
!     ---------------
!
      integer        :: i, j, k, l, m, ii, jj
      real(kind=RP)  :: xi, eta
      real(kind=RP)  :: dS(NDIM,0:Nel(1),0:Nel(2))
      real(kind=RP)  :: dSrot(NDIM,0:Nelf(1),0:Nelf(2))

      allocate( self % x(NDIM, 0:Nf(1), 0:Nf(2)))
      allocate( self % scal(0:Nf(1), 0:Nf(2)))
      allocate( self % normal(NDIM, 0:Nf(1), 0:Nf(2)))

      dS = 0.0_RP

      select case(side)
         case(ELEFT)
!
!           Get face coordinates
!           --------------------
            do j = 0, Nf(2) ; do i = 0, Nf(1)
               call coordRotation(spAf(1) % x(i), spAf(2) % x(j), rot, xi, eta)
               self % x(:,i,j) = hexMap % transfiniteMapAt([-1.0_RP, xi, eta])
            end do ; end do
!
!           Get surface Jacobian and normal vector
!           --------------------------------------
            do k = 0, Nel3D(3) ; do j = 0, Nel3D(2) ; do i = 0, Nel3D(1)
               dS(:,j,k) = dS(:,j,k) + geom % jGradXi(:,i,j,k) * spAe(1) % v(i,LEFT)
            end do           ; end do           ; end do
!
!           Swap orientation
!           ----------------
            dS = -dS
         
         case(ERIGHT)
!
!           Get face coordinates
!           --------------------
            do j = 0, Nf(2) ; do i = 0, Nf(1)
               call coordRotation(spAf(1) % x(i), spAf(2) % x(j), rot, xi, eta)
               self % x(:,i,j) = hexMap % transfiniteMapAt([ 1.0_RP, xi, eta ])
            end do ; end do
!
!           Get surface Jacobian and normal vector
!           --------------------------------------
            do k = 0, Nel3D(3) ; do j = 0, Nel3D(2) ; do i = 0, Nel3D(1)
               dS(:,j,k) = dS(:,j,k) + geom % jGradXi(:,i,j,k) * spAe(1) % v(i,RIGHT)
            end do           ; end do           ; end do
         
         case(EBOTTOM)
            do j = 0, Nf(2) ; do i = 0, Nf(1)
               call coordRotation(spAf(1) % x(i), spAf(2) % x(j), rot, xi, eta)
               self % x(:,i,j) = hexMap % transfiniteMapAt([xi, eta,-1.0_RP])
            end do ; end do
!
!           Get surface Jacobian and normal vector
!           --------------------------------------
            do k = 0, Nel3D(3) ; do j = 0, Nel3D(2) ; do i = 0, Nel3D(1)
               dS(:,i,j) = dS(:,i,j) + geom % jGradZeta(:,i,j,k) * spAe(3) % v(k,BOTTOM)
            end do           ; end do           ; end do
!
!           Swap orientation
!           ----------------
            dS = -dS
            
         case(ETOP)
            do j = 0, Nf(2) ; do i = 0, Nf(1)
               call coordRotation(spAf(1) % x(i), spAf(2) % x(j), rot, xi, eta)
               self % x(:,i,j) = hexMap % transfiniteMapAt([xi, eta, 1.0_RP])
            end do ; end do
!
!           Get surface Jacobian and normal vector
!           --------------------------------------
            do k = 0, Nel3D(3) ; do j = 0, Nel3D(2) ; do i = 0, Nel3D(1)
               dS(:,i,j) = dS(:,i,j) + geom % jGradZeta(:,i,j,k) * spAe(3) % v(k,TOP)
            end do           ; end do           ; end do
            
         case(EFRONT)
            do j = 0, Nf(2) ; do i = 0, Nf(1)
               call coordRotation(spAf(1) % x(i), spAf(2) % x(j), rot, xi, eta)
               self % x(:,i,j) = hexMap % transfiniteMapAt([xi, -1.0_RP, eta])
            end do ; end do
!
!           Get surface Jacobian and normal vector
!           --------------------------------------
            do k = 0, Nel3D(3) ; do j = 0, Nel3D(2) ; do i = 0, Nel3D(1)
               dS(:,i,k) = dS(:,i,k) + geom % jGradEta(:,i,j,k) * spAe(2) % v(j,FRONT)
            end do           ; end do           ; end do
!
!           Swap orientation
!           ----------------
            dS = -dS

         case(EBACK)
            do j = 0, Nf(2) ; do i = 0, Nf(1)
               call coordRotation(spAf(1) % x(i), spAf(2) % x(j), rot, xi, eta)
               self % x(:,i,j) = hexMap % transfiniteMapAt([xi, 1.0_RP, eta])
            end do ; end do
!
!           Get surface Jacobian and normal vector
!           --------------------------------------
            do k = 0, Nel3D(3) ; do j = 0, Nel3D(2) ; do i = 0, Nel3D(1)
               dS(:,i,k) = dS(:,i,k) + geom % jGradEta(:,i,j,k) * spAe(2) % v(j,BACK)
            end do           ; end do           ; end do

      end select
!
!     Change the orientation depending on whether left or right elements are used
!     ---------------------------------------------------------------------------
      if ( eSide .eq. 2 ) dS = -dS 
!
!     Perform the rotation
!     --------------------
      if ( rot .eq. 0 ) then
         dSRot = dS           ! Considered separated since is very frequent
   
      else
         do j = 0, Nelf(2) ; do i = 0, Nelf(1)
            call iijjIndexes(i,j,Nelf(1), Nelf(2), rot, ii, jj)
            dSRot(:,i,j) = dS(:,ii,jj)
         end do            ; end do

      end if
         
!
!     Perform p-Adaption
!     ------------------
      select case(projType)
      case (0)
         self % normal = dS
      case (1)
         self % normal = 0.0_RP
         do j = 0, Nf(2)  ; do l = 0, Nelf(1)   ; do i = 0, Nf(1)
            self % normal(:,i,j) = self % normal(:,i,j) + Tset(Nelf(1), Nf(1)) % T(i,l) * dS(:,l,j)
         end do                  ; end do                   ; end do
         
      case (2)
         self % normal = 0.0_RP
         do l = 0, Nelf(2)  ; do j = 0, Nf(2)   ; do i = 0, Nf(1)
            self % normal(:,i,j) = self % normal(:,i,j) + Tset(Nelf(2), Nf(2)) % T(j,l) * dS(:,i,l)
         end do                  ; end do                   ; end do

      case (3)
         self % normal = 0.0_RP
         do l = 0, Nelf(2)  ; do j = 0, Nf(2)   
            do m = 0, Nelf(1) ; do i = 0, Nf(1)
               self % normal(:,i,j) = self % normal(:,i,j) +   Tset(Nelf(1), Nf(1)) % T(i,m) &
                                         * Tset(Nelf(2), Nf(2)) % T(j,l) &
                                         * dS(:,m,l)
            end do                 ; end do
         end do                  ; end do
      end select
!
!     Compute
!     -------
      do j = 0, Nf(2)   ; do i = 0, Nf(1)
         self % scal(i,j) = norm2(self % normal(:,i,j))
         self % normal(:,i,j) = self % normal(:,i,j) / self % scal(i,j)
      end do            ; end do


   end subroutine ConstructMappedGeometryFace
!
!//////////////////////////////////////////////////////////////////////// 
!
      subroutine DestructMappedGeometryFace(self)
         implicit none
         !-------------------------------------------------------------------
         class(MappedGeometryFace), intent(inout) :: self
         !-------------------------------------------------------------------
         
         deallocate (self % x    )
         deallocate (self % scal  )
         deallocate (self % normal)
         
      end subroutine DestructMappedGeometryFace

!
!///////////////////////////////////////////////////////////////////////
!
!-------------------------------------------------------------------------------
!!     Returns the jacobian of the transformation computed from
!!     the three co-variant coordinate vectors.
!-------------------------------------------------------------------------------
!
      FUNCTION jacobian3D(a1,a2,a3)
!
      USE SMConstants
      IMPLICIT NONE

      REAL(KIND=RP)               :: jacobian3D
      REAL(KIND=RP), DIMENSION(3) :: a1,a2,a3,v
!
      CALL vCross(a2,a3,v)
      jacobian3D = vDot(a1,v)

      END FUNCTION jacobian3D
!
!///////////////////////////////////////////////////////////////////////////////
!
!-------------------------------------------------------------------------------
!!    Returns in result the cross product u x v
!-------------------------------------------------------------------------------
!
      SUBROUTINE vCross(u,v,result)
!
      IMPLICIT NONE
      
      REAL(KIND=RP), DIMENSION(3) :: u,v,result

      result(1) = u(2)*v(3) - v(2)*u(3)
      result(2) = u(3)*v(1) - v(3)*u(1)
      result(3) = u(1)*v(2) - v(1)*u(2)

      END SUBROUTINE vCross
!
!///////////////////////////////////////////////////////////////////////////////
!
!-------------------------------------------------------------------------------
!!    Returns the dot product u.v
!-------------------------------------------------------------------------------
!
      FUNCTION vDot(u,v)
!
      IMPLICIT NONE
      
      REAL(KIND=RP)               :: vDot
      REAL(KIND=RP), DIMENSION(3) :: u,v

      vDot = u(1)*v(1) + u(2)*v(2) + u(3)*v(3)

      END FUNCTION vDot
!
!///////////////////////////////////////////////////////////////////////////////
!
!-------------------------------------------------------------------------------
!!    Returns the 2-norm of u
!-------------------------------------------------------------------------------
!
      FUNCTION vNorm(u)
!
      IMPLICIT NONE
      
      REAL(KIND=RP)               :: vNorm
      REAL(KIND=RP), DIMENSION(3) :: u

      vNorm = SQRT(u(1)*u(1) + u(2)*u(2) + u(3)*u(3))

      END FUNCTION vNorm
!
!///////////////////////////////////////////////////////////////////////////////
!
      
END Module MappedGeometryClass
