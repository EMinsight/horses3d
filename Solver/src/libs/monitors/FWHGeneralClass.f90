!
!   @File:    ObserverClass.f90
!   @Author:  Oscar Marino (oscar.marino@upm.es)
!   @Created: Mar 25 2020
!   @Last revision date: 
!   @Last revision author: 
!   @Last revision commit: 
!
!//////////////////////////////////////////////////////
!
!This class represents the general behaviour of the Fwoc Williams and Hawckings aero accoustic analogy

#include "Includes.h"
Module FWHGeneralClass  !

    use SMConstants
    use MonitorDefinitions
    use FWHObseverClass
    use HexMeshClass
    use ZoneClass
    use FileReadingUtilities      , only: getFileName
    Implicit None

!
!   *****************************
!   Main FWH class definition
!   *****************************
    type FWHClass

        character(len=LINE_LENGTH)                                        :: solution_file
        integer                                                           :: numberOfObservers
        integer                                                           :: bufferLine
        real(kind=RP)                                                     :: dt_update
        integer, dimension(:), allocatable                                :: iter
        real(kind=RP), dimension(:), allocatable                          :: t
        class(ObserverClass), dimension(:), allocatable                   :: observers
        class(Zone_t), allocatable                                        :: sourceZone
        logical                                                           :: isSolid

        contains

            procedure :: construct      => FWHConstruct
            ! procedure :: destruct       => FWHDestruct
            ! procedure :: updateValues   => FWHUpate
            ! procedure :: writeToFile    => FWHWriteToFile

    end type FWHClass
           ! se debe construir desde la clase general de FW, esta debe hacer algo similar a la de monitores: crear update, escribir,
           ! crear archivo de escritura, allocar, leer de control file, etc...

    contains

    Subroutine FWHConstruct(self, mesh, controlVariables)
        use FTValueDictionaryClass
        use mainKeywordsModule
        use FileReadingUtilities, only: getCharArrayFromString
        implicit none

        class(FWHClass)                                     :: self
        class(HexMesh), intent(in)                          :: mesh
        class(FTValueDictionary), intent(in)                :: controlVariables

!       ---------------
!       Local variables
!       ---------------
!
        integer                                             :: fID , io
        integer                                             :: i
        character(len=STR_LEN_MONITORS)                     :: line
        character(len=STR_LEN_MONITORS)                     :: solution_file
        integer                                             :: no_of_zones, no_of_face_i
        integer, dimension(:), allocatable                  :: facesIDs, faces_per_zone, zonesIDs
        logical, save                                       :: FirstCall = .TRUE.
        character(len=LINE_LENGTH)                          :: zones_str
        character(len=LINE_LENGTH), allocatable             :: zones_names(:)

        allocate( self % t(BUFFER_SIZE), self % iter(BUFFER_SIZE) )

!       Get the general configuration of control file
!       --------------------------
        !TODO read accoustic analogy type and return if is not defined, check for FWH if is defined and not FWH stop and send error
        self % isSolid   = .not. controlVariables % logicalValueForKey("accoustic analogy permable")
        if (self % isSolid) then
            if (controlVariables % containsKey("accoustic solid surface")) then
                zones_str = controlVariables%stringValueForKey("accoustic solid surface", LINE_LENGTH)
            else 
                stop "Accoustic surface for integration is not defined"
            end if
            call getCharArrayFromString(zones_str, LINE_LENGTH, zones_names)

    !       Get the zones ids fo the mesh and for each the number of faces
    !       --------------------------
            no_of_zones = size(zones_names)
            allocate( faces_per_zone(no_of_zones), zonesIDs(no_of_zones) )
            do i = 1, no_of_zones
                zonesIDs(i) = getZoneID(zones_names(i), mesh)
                if (zonesIDs(i) .eq. -1) then
                    write(*,'(A,A,A)') "Warning: Accoustic surface ", trim(zones_names(i)), " not found in the mesh, will be ignored"
                    faces_per_zone(i) = 0
                else
                    faces_per_zone(i) = size(mesh % zones(zonesIDs(i)) % faces)
                end if
            end do 

    !       Get the faces Ids of all zones as a single array
    !       --------------------------
            allocate( facesIDs(SUM(faces_per_zone)) )
            no_of_face_i = 1
            do i = 1, no_of_zones
                if (zonesIDs(i) .eq. -1) cycle
                facesIDs(no_of_face_i:no_of_face_i+faces_per_zone(i)-1) = mesh % zones(zonesIDs(i)) % faces
                no_of_face_i = no_of_face_i + faces_per_zone(i) 
            end do 
        else
            stop "Permeable surfaces not implemented yet"
        end if

        ! create self sourceZone using facesIDs
!       --------------------------
        allocate( self % sourceZone )
        call self % sourceZone % CreateFicticious(-1, "FW_Surface", SUM(faces_per_zone), facesIDs)

!       Get the solution file name
!       --------------------------
        solution_file = controlVariables % stringValueForKey( solutionFileNameKey, requestedLength = STR_LEN_MONITORS )
!
!       Remove the *.hsol termination
!       -----------------------------
        solution_file = trim(getFileName(solution_file))
        self % solution_file = trim(solution_file)

!       Search in case file for probes, surface monitors, and volume monitors
!       ---------------------------------------------------------------------
        if (mesh % child) then ! Return doing nothing if this is a child mesh
           self % numberOfObservers = 0
        else
           self % numberOfObservers = getNoOfObservers()
        end if

!       Initialize observers
!       ----------
        allocate( self % observers(self % numberOfObservers) )
        do i = 1, self%numberOfObservers
            call self % observers(i) % construct(self % sourceZone, mesh, i, self % solution_file, FirstCall, self % isSolid)
        end do 

        self % bufferLine = 0
        
        FirstCall = .FALSE.

    End Subroutine FWHConstruct

!
!//////////////////////////////////////////////////////////////////////////////
!
!        Auxiliars
!
!//////////////////////////////////////////////////////////////////////////////
!
    Function getNoOfObservers() result(no_of_observers)
      use ParamfileRegions
      implicit none
      integer                        :: no_of_observers
!
!     ---------------
!     Local variables
!     ---------------
!
      character(len=LINE_LENGTH) :: case_name, line
      integer                    :: fID
      integer                    :: io
!
!     Initialize
!     ----------
      no_of_observers = 0
!
!     Get case file name
!     ------------------
      call get_command_argument(1, case_name)

!
!     Open case file
!     --------------
      open ( newunit = fID , file = case_name , status = "old" , action = "read" )

!
!     Read the whole file to find monitors
!     ------------------------------------
readloop:do 
         read ( fID , '(A)' , iostat = io ) line

         if ( io .lt. 0 ) then
!
!           End of file
!           -----------
            line = ""
            exit readloop

         elseif ( io .gt. 0 ) then
!
!           Error
!           -----
            errorMessage(STD_OUT)
            stop "Stopped."

         else
!
!           Succeeded
!           ---------
            line = getSquashedLine( line )

            if ( index ( line , '#defineaccousticobserver' ) .gt. 0 ) then
               no_of_observers = no_of_observers + 1

            end if
            
         end if

      end do readloop
!
!     Close case file
!     ---------------
      close(fID)                             

    End Function getNoOfObservers

    integer Function getZoneID(zone_name, mesh) result(n)

        character(len=*), intent(in)                        :: zone_name
        class(HexMesh), intent(in)                          :: mesh

        !local variables
        integer                                             :: zoneID

         n = -1
         do zoneID = 1, size(mesh % zones)
            if ( trim(mesh % zones(zoneID) % name) .eq. trim(zone_name) ) then
               n = zoneID
               exit
            end if
         end do

    End Function getZoneID

End Module FWHGeneralClass
