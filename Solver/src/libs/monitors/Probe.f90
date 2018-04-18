#if defined(NAVIERSTOKES)
module ProbeClass
   use SMConstants
   use HexMeshClass
   use MonitorDefinitions
   use PhysicsStorage
   use VariableConversion, only: Pressure
   use MPI_Process_Info
   use FluidData
#ifdef _HAS_MPI_
   use mpi
#endif
#include "Includes.h"
   
   private
   public   Probe_t
!
!  **********************
!  Probe class definition
!  **********************
!
   type Probe_t
      logical                         :: active
      integer                         :: rank
      integer                         :: ID
      integer                         :: eID
      real(kind=RP)                   :: x(NDIM)
      real(kind=RP)                   :: xi(NDIM)
      real(kind=RP)                   :: values(BUFFER_SIZE)
      real(kind=RP), allocatable      :: lxi(:) , leta(:), lzeta(:)
      character(len=STR_LEN_MONITORS) :: fileName
      character(len=STR_LEN_MONITORS) :: monitorName
      character(len=STR_LEN_MONITORS) :: variable
      contains
         procedure   :: Initialization => Probe_Initialization
         procedure   :: Update         => Probe_Update
         procedure   :: WriteLabel     => Probe_WriteLabel
         procedure   :: WriteValues    => Probe_WriteValue
         procedure   :: WriteToFile    => Probe_WriteToFile
         procedure   :: LookInOtherPartitions => Probe_LookInOtherPartitions
   end type Probe_t

   contains

      subroutine Probe_Initialization(self, mesh, ID, solution_file, FirstCall)
         use ParamfileRegions
         use MPI_Process_Info
         use Utilities, only: toLower
         implicit none
         class(Probe_t)          :: self
         class(HexMesh)          :: mesh
         integer                 :: ID
         character(len=*)        :: solution_file
         logical, intent(in)     :: FirstCall
!
!        ---------------
!        Local variables
!        ---------------
!
         integer                          :: i, j, k, fid
         character(len=STR_LEN_MONITORS)  :: in_label
         character(len=STR_LEN_MONITORS)  :: fileName
         character(len=STR_LEN_MONITORS)  :: paramFile
         character(len=STR_LEN_MONITORS)  :: coordinates
         real(kind=RP)                    :: x(NDIM)
         interface
            function getArrayFromString( line ) result ( array )
               use SMConstants
               implicit none
               character(len=*),    intent(in)  :: line
               real(kind=RP), allocatable       :: array(:)
            end function getArrayFromString
         end interface
!
!        Get monitor ID
!        --------------
         self % ID = ID
!
!        Search for the parameters in the case file
!        ------------------------------------------
         write(in_label , '(A,I0)') "#define probe " , self % ID
         
         call get_command_argument(1, paramFile)
         call readValueInRegion(trim(paramFile), "Name"    , self % monitorName, in_label, "# end" )
         call readValueInRegion(trim(paramFile), "Variable", self % variable   , in_label, "# end" )
         call readValueInRegion(trim(paramFile), "Position", coordinates       , in_label, "# end" )
!
!        Get the coordinates
!        -------------------
         x = getArrayFromString(coordinates)
!
!        Check the variable
!        ------------------
         call tolower(self % variable)

         select case ( trim(self % variable) )
         case ("pressure")
         case ("velocity")
         case ("u")
         case ("v")
         case ("w")
         case ("mach")
         case ("k")
         case default
            print*, 'Probe variable "',trim(self % variable),'" not implemented.'
            print*, "Options available are:"
            print*, "   * pressure"
            print*, "   * velocity"
            print*, "   * u"
            print*, "   * v"
            print*, "   * w"
            print*, "   * Mach"
            print*, "   * K"
         end select
!
!        Find the requested point in the mesh
!        ------------------------------------
         self % active = mesh % FindPointWithCoords(x, self % eID, self % xi)
!
!        Check whether the probe is located in other partition
!        -----------------------------------------------------
         call self % LookInOtherPartitions
!
!        Disable the probe if the point is not found
!        -------------------------------------------
         if ( .not. self % active ) then
            if ( MPI_Process % isRoot ) then
               write(STD_OUT,'(A,I0,A)') "Probe ", ID, " was not successfully initialized."
               print*, "Probe is set to inactive."
            end if

            return
         end if
!
!        Set the fileName
!        ----------------
         write( self % fileName , '(A,A,A,A)') trim(solution_file) , "." , &
                                               trim(self % monitorName) , ".probe"  
!
!
!        Return if the process does not contain the partition
!        ----------------------------------------------------
         if ( self % rank .ne. MPI_Process % rank ) then
            self % eID = 1
            return
         end if
!
!        Get the Lagrange interpolants
!        -----------------------------
         associate(e => mesh % elements(self % eID))
         allocate( self % lxi(0 : e % Nxyz(1)) )
         allocate( self % leta(0 : e % Nxyz(2)) )
         allocate( self % lzeta(0 : e % Nxyz(3)) )
         self % lxi = e % spAxi % lj(self % xi(1))
         self % leta = e % spAeta % lj(self % xi(2))
         self % lzeta = e % spAzeta % lj(self % xi(3))
!
!        Recover the coordinates from direct projection. These will be the real coordinates
!        ----------------------------------------------
         self % x = 0.0_RP
         do k = 0, e % Nxyz(3)   ; do j = 0, e % Nxyz(2) ; do i = 0, e % Nxyz(1)
            self % x = self % x + e % geom % x(:,i,j,k) * self % lxi(i) * self % leta(j) * self % lzeta(k)
         end do                  ; end do                ; end do 
!
!        ****************
!        Prepare the file
!        ****************
!
!        Create file
!        -----------
         if (FirstCall) then
            open ( newunit = fID , file = trim(self % fileName) , status = "unknown" , action = "write" ) 
!
!        Write the file headers
!        ----------------------
            write( fID , '(A20,A  )') "Monitor name:      ", trim(self % monitorName)
            write( fID , '(A20,A  )') "Selected variable: " , trim(self % variable)
            write( fID , '(A20,ES24.10)') "x coordinate: ", self % x(1)
            write( fID , '(A20,ES24.10)') "y coordinate: ", self % x(2)
            write( fID , '(A20,ES24.10)') "z coordinate: ", self % x(3)

            write( fID , * )
            write( fID , '(A10,2X,A24,2X,A24)' ) "Iteration" , "Time" , trim(self % variable)

            close ( fID )
         end if
         end associate
      end subroutine Probe_Initialization

      subroutine Probe_Update(self, mesh, bufferPosition)
         use Physics
         use MPI_Process_Info
         implicit none
         class(Probe_t) :: self
         class(HexMesh)                   :: mesh
         integer                          :: bufferPosition
!
!        ---------------
!        Local variables
!        ---------------
!
         integer        :: i, j, k, ierr
         real(kind=RP)  :: value
         real(kind=RP)  :: var(0:mesh % elements(self % eID) % Nxyz(1),&
                               0:mesh % elements(self % eID) % Nxyz(2),&
                               0:mesh % elements(self % eID) % Nxyz(3)  )

         if ( .not. self % active ) return 

         if ( MPI_Process % rank .eq. self % rank ) then
!
!           Update the probe
!           ----------------
            associate( e => mesh % elements(self % eID) )
            associate( Q => e % storage % Q )
   
            select case (trim(self % variable))
            case("pressure")
               do k = 0, e % Nxyz(3) ; do j = 0, e % Nxyz(2)  ; do i = 0, e % Nxyz(1) 
                  var(i,j,k) = Pressure(Q(:,i,j,k))
               end do            ; end do             ; end do
   
            case("velocity")
               do k = 0, e % Nxyz(3) ; do j = 0, e % Nxyz(2) ; do i = 0, e % Nxyz(1)
                  var(i,j,k) = sqrt(POW2(Q(IRHOU,i,j,k)) + POW2(Q(IRHOV,i,j,k)) + POW2(Q(IRHOW,i,j,k)))/Q(IRHO,i,j,k)
               end do         ; end do         ; end do
   
            case("u")
               do k = 0, e % Nxyz(3) ; do j = 0, e % Nxyz(2)  ; do i = 0, e % Nxyz(1) 
                  var(i,j,k) = Q(IRHOU,i,j,k) / Q(IRHO,i,j,k)
               end do            ; end do             ; end do
   
            case("v")
               do k = 0, e % Nxyz(3) ; do j = 0, e % Nxyz(2)  ; do i = 0, e % Nxyz(1) 
                  var(i,j,k) = Q(IRHOV,i,j,k) / Q(IRHO,i,j,k)
               end do            ; end do             ; end do
   
            case("w")
               do k = 0, e % Nxyz(3) ; do j = 0, e % Nxyz(2)  ; do i = 0, e % Nxyz(1) 
                  var(i,j,k) = Q(IRHOW,i,j,k) / Q(IRHO,i,j,k)
               end do            ; end do             ; end do
   
            case("mach")
               do k = 0, e % Nxyz(3) ; do j = 0, e % Nxyz(2) ; do i = 0, e % Nxyz(1)
                  var(i,j,k) = POW2(Q(IRHOU,i,j,k)) + POW2(Q(IRHOV,i,j,k)) + POW2(Q(IRHOW,i,j,k))/POW2(Q(IRHO,i,j,k))     ! Vabs**2
                  var(i,j,k) = sqrt( var(i,j,k) / ( thermodynamics % gamma*(thermodynamics % gamma-1.0_RP)*(Q(IRHOE,i,j,k)/Q(IRHO,i,j,k)-0.5_RP * var(i,j,k)) ) )
               end do         ; end do         ; end do
      
            case("k")
               do k = 0, e % Nxyz(3) ; do j = 0, e % Nxyz(2) ; do i = 0, e % Nxyz(1)
                  var(i,j,k) = 0.5_RP * (POW2(Q(IRHOU,i,j,k)) + POW2(Q(IRHOV,i,j,k)) + POW2(Q(IRHOW,i,j,k)))/Q(IRHO,i,j,k)
               end do         ; end do         ; end do
   
            end select
   
            value = 0.0_RP
            do k = 0, e % Nxyz(3)    ; do j = 0, e % Nxyz(2)  ; do i = 0, e % Nxyz(1)
               value = value + var(i,j,k) * self % lxi(i) * self % leta(j) * self % lzeta(k)
            end do               ; end do             ; end do
   
            self % values(bufferPosition) = value
   
            end associate
            end associate
#ifdef _HAS_MPI_            
            if ( MPI_Process % doMPIAction ) then
!
!              Share the result with the rest of the processes
!              -----------------------------------------------         
               call mpi_bcast(value, 1, MPI_DOUBLE, self % rank, MPI_COMM_WORLD, ierr)

            end if
#endif
         else
!
!           Receive the result from the rank that contains the probe
!           --------------------------------------------------------
#ifdef _HAS_MPI_
            if ( MPI_Process % doMPIAction ) then
               call mpi_bcast(self % values(bufferPosition), 1, MPI_DOUBLE, self % rank, MPI_COMM_WORLD, ierr)
            end if
#endif
         end if
      end subroutine Probe_Update

      subroutine Probe_WriteLabel ( self )
!
!        *************************************************************
!              This subroutine writes the label for the probe,
!           when invoked from the time integrator Display
!           procedure.
!        *************************************************************
!
         implicit none
         class(Probe_t)             :: self

         write(STD_OUT , '(3X,A10)' , advance = "no") trim(self % monitorName(1 : MONITOR_LENGTH))

      end subroutine Probe_WriteLabel

      subroutine Probe_WriteValue ( self , bufferLine ) 
!
!        *************************************************************
!              This subroutine writes the monitor value for the time
!           integrator Display procedure.
!        *************************************************************
!
         implicit none
         class(Probe_t) :: self
         integer                 :: bufferLine

         write(STD_OUT , '(1X,A,1X,ES10.3)' , advance = "no") "|" , self % values ( bufferLine ) 

      end subroutine Probe_WriteValue 

      subroutine Probe_WriteToFile ( self , iter , t , no_of_lines)
!
!        *************************************************************
!              This subroutine writes the buffer to the file.
!        *************************************************************
!
         implicit none  
         class(Probe_t) :: self
         integer                 :: iter(:)
         real(kind=RP)           :: t(:)
         integer                 :: no_of_lines
!
!        ---------------
!        Local variables
!        ---------------
!
         integer                    :: i
         integer                    :: fID

         if ( MPI_Process % isRoot ) then
            open( newunit = fID , file = trim ( self % fileName ) , action = "write" , access = "append" , status = "old" )
         
            do i = 1 , no_of_lines
               write( fID , '(I10,2X,ES24.16,2X,ES24.16)' ) iter(i) , t(i) , self % values(i)

            end do
        
            close ( fID )
         end if

         
         if ( no_of_lines .ne. 0 ) self % values(1) = self % values(no_of_lines)
      
      end subroutine Probe_WriteToFile

      subroutine Probe_LookInOtherPartitions(self)
         use MPI_Process_Info
         implicit none
         class(Probe_t)    :: self
         integer           :: allActives(MPI_Process % nProcs)
         integer           :: active, ierr

         if ( MPI_Process % doMPIAction ) then
#ifdef _HAS_MPI_
!
!           Cast the logicals onto integers
!           -------------------------------
            if ( self % active ) then
               active = 1
            else
               active = 0
            end if
!
!           Gather all data from all processes
!           ----------------------------------
            call mpi_allgather(active, 1, MPI_INT, allActives, 1, MPI_INT, MPI_COMM_WORLD, ierr)
!
!           Check if any of them found the probe
!           ------------------------------------
            if ( any(allActives .eq. 1) ) then
!
!              Assign the domain of the partition that contains the probe
!              ----------------------------------------------------------
               self % active = .true.
               self % rank = maxloc(allActives, dim = 1) - 1

            else
!
!              Disable the probe
!              -----------------
               self % active = .false.
               self % rank   = -1

            end if
#endif
         else
!
!           Without MPI select the rank 0 as default
!           ----------------------------------------
            self % rank = 0

         end if

      end subroutine Probe_LookInOtherPartitions

end module ProbeClass
#endif
