*     ------------------------------------------------------------------
*     File slmainMPS.f
*     SQOPT is used to solve an LP input from an MPS file.
*     The problem is the diet problem.
*
*     04 Oct 1994: First   version.
*     28 Oct 2003: Current version.
*     ------------------------------------------------------------------
      program
     &     slmain
      implicit
     &     none

      integer
     &     maxm, maxn, maxne
      parameter
     &   ( maxm   = 1000,
     &     maxn   = 1500,
     &     maxne  = 3000 )

      character
     &     PrbNms(5)*8, Names(maxm+maxn)*8
      integer
     &     indA(maxne), eType(maxn+maxm), hs(maxn+maxm), locA(maxn+1)
      double precision
     &     Acol(maxne), bl(maxn+maxm), bu(maxn+maxm),
     &     cObj(maxn), x(maxn+maxm), pi(maxm), rc(maxn+maxm)
*     ------------------------------------------------------------------
*     SQOPT workspace
      integer
     &     lencw, leniw, lenrw
      parameter
     &   ( lenrw = 50000, leniw =  60000, lencw =   500)
      double precision
     &     rw(lenrw)
      integer
     &     iw(leniw)
      character
     &     cw(lencw)*8
*     ------------------------------------------------------------------
      external
     &     nullHx
      integer
     &     Errors, i1, i2, INFO, iMPS, iObj, iPrint, iSumm, iSpecs,
     &     itnlim, j, lencObj, m, mincw, miniw, minrw, n, ncolH, ne,
     &     nInf, nName, nnCon, nnJac, nnObj, nOut, nS
      double precision
     &     Obj, ObjAdd, sInf
      logical
     &     byname
      character
     &     lfile*20
*     ------------------------------------------------------------------
*     Specify some of the SNOPT files.
*     iSpecs  is the Specs file   (0 if none).
*     iPrint  is the Print file   (0 if none).
*     iSumm   is the Summary file (0 if none).
*
*     nOut    is an output file used here by main.

      iSpecs =  4
      iPrint =  9
      iSumm  =  6
      nOut   =  6

      byname = .true.

      if ( byname ) then

*        Unix and DOS systems.  Open the Specs and print files.

         lfile = 'slmainMPS.spc'
         open( iSpecs, file=lfile, status='OLD',     err=800 )

         lfile = 'slmainMPS.out'
         open( iPrint, file=lfile, status='UNKNOWN', err=800 )
      end if

*     ------------------------------------------------------------------
*     First,  sqInit MUST be called to initialize optional parameters
*     to their default values.
*     ------------------------------------------------------------------
      call sqInit
     &   ( iPrint, iSumm, cw, lencw, iw, leniw, rw, lenrw )

*     ------------------------------------------------------------------
*     Read a Specs file (Optional).
*     ------------------------------------------------------------------
      call sqSpec
     &   ( iSpecs, INFO, cw, lencw, iw, leniw, rw, lenrw )

      if (INFO .ne. 101  .and.  INFO .ne. 107) then
         go to 910
      end if

*     ------------------------------------------------------------------
*     Set up the data structure for the constraints.
*     MPSinp needs to know the values of nnCon, nnJac, and nnObj
*     (all zero for linear constraints).
*     The calls to sqget fetch values or defaults set in the SPECS file.
*     Optionally, these values can be set in-line.
*     ------------------------------------------------------------------
      Errors = 0

      call sqgeti
     &   ( 'Nonlinear constraints        ', nnCon, Errors,
     &     cw, lencw, iw, leniw, rw, lenrw )
      call sqgeti
     &   ( 'Nonlinear Jacobian  variables', nnJac, Errors,
     &     cw, lencw, iw, leniw, rw, lenrw )
      call sqgeti
     &   ( 'Nonlinear Objective variables', nnObj, Errors,
     &     cw, lencw, iw, leniw, rw, lenrw )
      call sqgeti
     &   ( 'MPS file                     ',  iMPS, Errors,
     &     cw, lencw, iw, leniw, rw, lenrw )

*     The problem name is not needed---it is set by MPSinp.
*     Specify the OBJECTIVE, RHS, RANGES and BOUNDS to be selected
*     from the MPS file.  Blank names mean "select the first one".

*     PrbNms(1) = '        '    ! PROBLEM   name
      PrbNms(2) = '        '    ! OBJECTIVE name
      PrbNms(3) = '        '    ! RHS       name
      PrbNms(4) = '        '    ! RANGES    name
      PrbNms(5) = '        '    ! BOUNDS    name

      if ( byname ) then

*        Unix and DOS systems.  Open the MPS file.

         lfile = 'slmainMPS.mps'
         open( iMPS, file=lfile, status='OLD', err=800 )
      end if

      call MPSinp
     &   ( iMPS, maxm, maxn, maxne,
     &     nnCon, nnJac, nnObj,
     &     m, n, ne,
     &     iObj, ObjAdd, PrbNms,
     &     Acol, indA, locA, bl, bu, Names,
     &     hs, x, pi,
     &     INFO, mincw, miniw, minrw, nS,
     &     cw, lencw, iw, leniw, rw, lenrw )
      close( iMPS )
      if (INFO .ne. 103) go to 990

      nName = m + n

*     ------------------------------------------------------------------
*     Fix the column variables to be non-elastic and the row  variables
*     to be elastic.
*     ------------------------------------------------------------------
      ncolH   = 0
      lencObj = 0

      do j = 1, n
         eType(j) = 0
      end do

      do j = n+1, n+m
         eType(j) = 3
      end do

*     ------------------------------------------------------------------
*     Specify options that were not set in the Specs file.
*     i1 and i2 may refer to the Print and Summary file respectively.
*     Setting them to 0 suppresses printing.
*     ------------------------------------------------------------------
      itnlim = 4000
      i1     =  0
      i2     =  0
      call sqseti
     &   ( 'Iterations        ', itnlim, i1, i2, Errors,
     &     cw, lencw, iw, leniw, rw, lenrw )
      call sqset      ! Required for following Warm start call
     &   ( 'Sticky parameters yes', i1, i2, Errors,
     &     cw, lencw, iw, leniw, rw, lenrw )

*     ------------------------------------------------------------------
*     Go for it, using a Cold start.
*     hs     need not be set if a basis file is to be input.
*            Otherwise, each hs(1:n) should be 0, 1, 2, 3, 4, or 5.
*            The values are used by the Crash procedure s2crsh
*            to choose an initial basis B.
*            If hs(j) = 0 or 1, column j is eligible for B.
*            If hs(j) = 2, column j is initially superbasic (not in B).
*            If hs(j) = 3, column j is eligible for B and is given
*                          preference over columns with hs(j) = 0 or 1.
*            If hs(j) = 4 or 5, column j is initially nonbasic.
*
*     No user-workspace, so we use cw, iw, rw.
*     ------------------------------------------------------------------
      call sqopt
     &   ( 'Cold', nullHx, m,
     &     n, ne, nName, lencObj, ncolH,
     &     iObj, ObjAdd, PrbNms(1),
     &     Acol, indA, locA, bl, bu, cObj, Names,
     &     eType, hs, x, pi, rc,
     &     INFO, mincw, miniw, minrw,
     &     nS, nInf, sInf, Obj,
     &     cw, lencw, iw, leniw, rw, lenrw,
     &     cw, lencw, iw, leniw, rw, lenrw )

      if (INFO .eq. 82 .or. INFO .eq. 83 .or. INFO .eq. 84) then
         go to 910
      end if

      write(nOut, *) ' '
      write(nOut, *) 'slmainMPS (1) finished.'
      write(nOut, *) 'Input  errors =', Errors
      write(nOut, *) 'snOptB INFO   =', INFO
      write(nOut, *) 'nInf          =', nInf
      write(nOut, *) 'sInf          =', sInf
      if (iObj .gt. 0) then
         write(nOut, *) 'Obj        =', ObjAdd + x(n+iObj) + Obj
      else
         write(nOut, *) 'Obj        =', ObjAdd + Obj
      end if
      if (INFO .gt. 30) go to 910

*     ------------------------------------------------------------------
*     Alter some options and call sqopt again, testing the Warm start.
*     The following illustrates the use of sqset, sqseti and sqsetr
*     to set specific options.  If necessary, we could ensure that
*     all unspecified options take default values
*     by first calling sqset ( 'Defaults', ... ).
*     Beware that certain parameters would then need to be redefined.
*     ------------------------------------------------------------------
      write(nOut, *) ' '
      write(nOut, *) 'Alter options and test Warm start:'

      Errors   = 0
      itnlim = 500
      call sqset ( '                  ',         iPrint, iSumm, Errors,
     &             cw, lencw, iw, leniw, rw, lenrw )
      call sqset ( 'Print  level     0',         iPrint, iSumm, Errors,
     &             cw, lencw, iw, leniw, rw, lenrw )
      call sqset ( 'Scale option     0',         iPrint, iSumm, Errors,
     &             cw, lencw, iw, leniw, rw, lenrw )
      call sqseti( 'Iterations        ', itnlim, iPrint, iSumm, Errors,
     &             cw, lencw, iw, leniw, rw, lenrw )

      if (Errors .gt. 0) then
         write(nOut, *) 'NOTE: Some of the options were not recognized'
      end if
*     ------------------------------------------------------------------
*     Test the Warm start.
*     hs(*) specifies a complete basis from the previous call.
*     A Warm start uses hs(*) directly, without calling Crash.
*
*     Warm starts are normally used after sqopt has solved a
*     problem with the SAME DIMENSIONS but perhaps altered data.
*     Here we have not altered the data, so very few iterations
*     should be required.
*     ------------------------------------------------------------------
      call sqopt
     &   ( 'Warm', nullHx, m,
     &     n, ne, nName, lencObj, ncolH,
     &     iObj, ObjAdd, PrbNms(1),
     &     Acol, indA, locA, bl, bu, cObj, Names,
     &     eType, hs, x, pi, rc,
     &     INFO, mincw, miniw, minrw,
     &     nS, nInf, sInf, Obj,
     &     cw, lencw, iw, leniw, rw, lenrw,
     &     cw, lencw, iw, leniw, rw, lenrw )

      write(nOut, *) ' '
      write(nOut, *) 'slmainMPS (2) finished.'
      write(nOut, *) 'Input  errors =', Errors
      write(nOut, *) 'snOptB INFO   =', INFO
      write(nOut, *) 'nInf          =', nInf
      write(nOut, *) 'sInf          =', sInf
      if (iObj .gt. 0) then
         write(nOut, *) 'Obj        =', ObjAdd + x(n+iObj) + Obj
      else
         write(nOut, *) 'Obj        =', ObjAdd + Obj
      end if
      if (INFO .gt. 30) go to 910

      stop

*     ------------------------------------------------------------------
*     Error exit.
*     ------------------------------------------------------------------
  800 write(nOut, 4000) 'Error while opening file', lfile
      stop

  910 write(nOut, *) ' '
      write(nOut, *) 'STOPPING because of error condition'

  990 stop

 4000 format(/  a, 2x, a  )

      end ! program slmainMPS
