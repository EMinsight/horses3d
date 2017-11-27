#include "Includes.h"
module getInputData_MOD
   use SMConstants
   implicit none

   private
   public getInputData

   public MeshFileKey, SolutionFileKey, GeometryKey, CubeLengthKey, CubeCenterKey, NPointsKey

   character(len=*), parameter   :: GEOMETRY_FLAG='--geometry='
   character(len=*), parameter   :: CUBELENGTH_FLAG='--cube-length='
   character(len=*), parameter   :: CUBECENTER_FLAG='--cube-center='
   character(len=*), parameter   :: NPOINTS_FLAG='--npoints='

   character(len=*), parameter   :: MeshFileKey     = "Mesh file"
   character(len=*), parameter   :: SolutionFileKey = "Solution file"
   character(len=*), parameter   :: GeometryKey     = "Geometry"
   character(len=*), parameter   :: CubeLengthKey   = "Cube length"
   character(len=*), parameter   :: CubeCenterKey   = "Cube center"
   character(len=*), parameter   :: NPointsKey  = "npoints"


   contains
      subroutine getInputData(controlVariables)
         use FTValueDictionaryClass
         implicit none
         class(FTValueDictionary),  intent(inout)  :: controlVariables
!
!        ---------------
!        Local variables
!        ---------------
!
         integer     :: narg, pos, i
         character(len=LINE_LENGTH) :: line
!
!        Get number of command line arguments
!        ------------------------------------
         narg = command_argument_count()
!
!        Exit if not enough command arguments are present
!        ----------------------------------------
         if ( narg .lt. 2 ) then 
            print*, "No mesh and/or solution files indicated."
            print*, "Syntax is: horses.geometry meshfile.mesh solutionfile.hsol"
            errorMessage(STD_OUT)
            stop
         end if
!
!        First argument is always the mesh file
!        --------------------------------------
         call get_command_argument(1,line)
         call controlVariables % addValueForKey(trim(line),MeshFileKey)
!
!        Second argument is always the solution file
!        -------------------------------------------
         call get_command_argument(2,line)
         call controlVariables % addValueForKey(trim(line),SolutionFileKey)
!
!        Get geometry flags 
!        ------------------
         do i = 3, narg
            call get_command_argument(i, line)
!
!           Geometry
!           --------
            pos = index(trim(line), GEOMETRY_FLAG)
            if ( pos .ne. 0 ) then
               read(line(pos+len_trim(GEOMETRY_FLAG):len_trim(line)),*) line
               call controlVariables % addValueForKey(trim(line), GeometryKey)
               cycle
            end if
!
!           Cube side length
!           ----------------
            pos = index(trim(line), CUBELENGTH_FLAG)
            if ( pos .ne. 0 ) then
               read(line(pos+len_trim(CUBELENGTH_FLAG):len_trim(line)),*) line
               call controlVariables % addValueForKey(trim(line), CubeLengthKey)
               cycle
            end if
!
!           Cube center
!           -----------
            pos = index(trim(line), CUBECENTER_FLAG)
            if ( pos .ne. 0 ) then
               read(line(pos+len_trim(CUBECENTER_FLAG):len_trim(line)),'(A)') line
               call controlVariables % addValueForKey(trim(line), CubeCenterKey)
               cycle
            end if
!
!           Cube npoints
!           ------------
            pos = index(trim(line), NPOINTS_FLAG)
            if ( pos .ne. 0 ) then
               read(line(pos+len_trim(NPOINTS_FLAG):len_trim(line)),*) line
               call controlVariables % addValueForKey(trim(line), NPointsKey)
               cycle
            end if

         end do
!
!        Set default values
!        ------------------
         if ( .not. controlVariables % ContainsKey(GeometryKey) ) then
            call controlVariables % addValueForKey("Cube",GeometryKey)
         end if

         
      end subroutine getInputData

end module getInputData_MOD