!////////////////////////////////////////////////////////////////////////
!
!      PETScMatrixClass.f90
!      Created: 2018-02-19 17:07:00 +0100 
!      By: Andrés Rueda
!
!      Class for sparse block diagonal matrices
!      -> The matrix is not dense, the block is!
!
!////////////////////////////////////////////////////////////////////////
module DenseBlockDiagonalMatrixClass
   use SMConstants
   use GenericMatrixClass
   implicit none
   
   private
   public DenseBlockDiagMatrix_t, Matrix_t, Block_t
   
   type Block_t
      real(kind=RP), pointer, contiguous :: Matrix(:,:)
      integer      , pointer, contiguous :: Indexes(:)
   end type Block_t
   
   type, extends(Matrix_t) :: DenseBlockDiagMatrix_t
      type(Block_t), allocatable :: Blocks(:)   ! Array containing each block in a dense matrix
      integer                    :: NumOfBlocks ! Number of blocks in matrix
      integer      , allocatable :: BlockSizes(:)
      integer      , allocatable :: BlockIdx(:)
      contains
         procedure :: construct
         procedure :: Preallocate
         procedure :: Reset
         procedure :: SetColumn
         procedure :: shift
   end type DenseBlockDiagMatrix_t
contains
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   subroutine construct(this,dimPrb,withMPI)
      implicit none
      !---------------------------------------------
      class(DenseBlockDiagMatrix_t) :: this     !<> This matrix
      integer          , intent(in) :: dimPrb   !<  Number of blocks of the matrix!
      logical, optional, intent(in) :: WithMPI
      !---------------------------------------------
      
      allocate ( this % Blocks(dimPrb) )
      this % NumOfBlocks = dimPrb
      allocate ( this % BlockSizes(dimPrb) )
      allocate ( this % BlockIdx(dimPrb+1) )
      
   end subroutine construct
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   subroutine Preallocate(this, nnz, nnzs)
      IMPLICIT NONE
      !---------------------------------------------
      class(DenseBlockDiagMatrix_t), intent(inout) :: this    !<> This matrix
      integer, optional            , intent(in)    :: nnz     !<  Not needed here
      integer, optional            , intent(in)    :: nnzs(:) !<  nnzs contains the block sizes!
      !---------------------------------------------
      integer :: i, k ! counters
      !---------------------------------------------
      
      if (.not. present(nnzs) ) ERROR stop ':: DenseBlockDiagMatrix needs the block sizes'
      if ( size(nnzs) /= this % NumOfBlocks) ERROR stop ':: DenseBlockDiagMatrix: wrong dimension for the block sizes'
      
      this % BlockSizes = nnzs
      this % NumRows = sum(nnzs)
      
      this % BlockIdx(1) = 1
      do i=2, this % NumOfBlocks + 1
         this % BlockIdx(i) = this % BlockIdx(i-1) + nnzs(i-1)
      end do
      
!$omp parallel do private(k) schedule(runtime)
      do i=1, this % NumOfBlocks
         allocate ( this % Blocks(i) % Matrix(nnzs(i),nnzs(i)) )
         allocate ( this % Blocks(i) % Indexes(nnzs(i)) )
         
         this % Blocks(i) % Indexes = (/ (k, k=this % BlockIdx(i),this % BlockIdx(i+1) - 1 ) /)
         
      end do
!$omp end parallel do      
   end subroutine Preallocate
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   subroutine Reset(this)
      IMPLICIT NONE
      !---------------------------------------------
      class(DenseBlockDiagMatrix_t), intent(inout) :: this     !<> This matrix
      !---------------------------------------------
      integer :: i
      !---------------------------------------------
      
      do i=1, this % NumOfBlocks
         this % Blocks(i) % Matrix = 0._RP
      end do
      
   end subroutine Reset
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   subroutine SetColumn(this,nvalues, irow, icol, values )
      implicit none
      !---------------------------------------------
      class(DenseBlockDiagMatrix_t), intent(inout) :: this
      integer                      , intent(in)    :: nvalues
      integer, dimension(:)        , intent(in)    :: irow
      integer                      , intent(in)    :: icol
      real(kind=RP), dimension(:)  , intent(in)    :: values
      !---------------------------------------------
      integer :: thisblock, thiscol, thisrow, firstIdx, lastIdx
      integer :: i
      integer, pointer :: indexes(:)
      !---------------------------------------------
      
      if ( (icol > this % NumRows) .or. (icol < 1) ) ERROR stop ':: DenseBlockDiagMatrix: icol value is out of bounds'
      
      ! Search the corresponding block (they are ordered)
      do thisblock=1, this % NumOfBlocks
         if (icol <= this % BlockIdx(thisblock+1) -1) exit
      end do
      
      indexes => this % Blocks(thisblock) % Indexes
      firstIdx = this % BlockIdx(thisblock)
      lastIdx  = this % BlockIdx(thisblock+1) - 1
      
      ! Get relative position of column
      do thiscol=1, this % BlockSizes(thisblock)
         if (icol == indexes(thiscol)) exit
      end do
      
      ! Fill the column info
      do i=1, nvalues
         if ( irow(i) < firstIdx .or. irow(i) > lastIdx ) cycle
         ! Get relative row
         do thisrow=1, this % BlockSizes(thisblock)
            if (irow(i) == indexes(thisrow)) exit
         end do
         this % Blocks(thisblock) % Matrix(thisrow,thiscol) = values(i)
      
      end do
      
      nullify(indexes)
      
   end subroutine SetColumn
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   subroutine shift(this,shiftval)
      implicit none
      !------------------------------------------
      class(DenseBlockDiagMatrix_t), intent(inout) :: this
      real(kind=RP)                , intent(in)    :: shiftval
      !------------------------------------------
      INTEGER                :: i, iBL
      real(kind=RP), pointer :: Mat_p(:,:)
      !------------------------------------------
      
!$omp parallel do private(i,Mat_p) schedule(runtime)
      do iBL=1, this % NumOfBlocks
         Mat_p => this % Blocks(iBL) % Matrix
         do i=1, size(Mat_p,1)
            Mat_p(i,i) = Mat_p(i,i) + shiftval
         end do
      end do
!$omp end parallel do
      
   end subroutine shift
   
end module DenseBlockDiagonalMatrixClass
