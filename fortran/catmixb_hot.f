*     ------------------------------------------------------------------
*     File catmixb_hot.f
*
*     The AMPL model is:
*
*     param tf := 1;      # Final time
*     param nh;           # Number of subintervals
*     param x1_0;         # Initial condition for x1
*     param x2_0;         # Initial condition for x2
*
*     param alpha;        # smoothing parameter;
*
*     param h := tf/nh;
*
*     var  u {0..nh} <= 1, >= 0;
*     var x1 {0..nh};
*     var x2 {0..nh};
*
*     minimize objective:  -1 + x1[nh] + x2[nh]
*                             + alpha*h*sum{i in 0..nh-1} (u[i+1] - u[i])^2 ;
*
*     subject to ode1 {i in 0..(nh-1)}:
*     x1[i+1] = x1[i] + (h/2)*(u[i]*(10*x2[i]-x1[i]) + u[i+1]*(10*x2[i+1]-x1[i+1]));
*
*     subject to ode2 {i in 0..(nh-1)}:
*     x2[i+1] = x2[i] + (h/2)*(u[i]*(x1[i]-10*x2[i]) - (1-u[i])*x2[i] +
*                              u[i+1]*(x1[i+1]-10*x2[i+1]) - (1-u[i+1])*x2[i+1]);
*
*     subject to ic1:
*     x1[0] = x1_0;
*
*     subject to ic2:
*     x2[0] = x2_0;
*
*     Data:
*     param nh   := 800;
*     param x1_0 := 1;
*     param x2_0 := 0;
*     param alpha:= 0.0;;
*
*     let {i in 0..nh}  u[i] := 0;
*     let {i in 0..nh} x1[i] := 1;
*     let {i in 0..nh} x2[i] := 0;
*
*     15 Dec 2004: First version of catmixb, derived from catmixa.
*     08 Apr 2008: Acol initialized, as required in the documentation.
*     ------------------------------------------------------------------
      program
     &     catmixb

      implicit
     &     none
      integer
     &     maxnh, maxm, maxn, maxne, nName, i1, i2
      parameter
     &   ( maxnh  = 2000,
     &     maxm   = 2*maxnh,
     &     maxn   = 3*maxnh + 2,
     &     maxne  = 7*maxnh,
     &     nName  = 1 )

      character
     &     ProbNm*8, Names(nName)*8
      integer
     &     indA(maxne) , hs(maxm+maxn), locA(maxn+1)
      double precision
     &     Acol(maxne) , bl(maxm+maxn), bu(maxm+maxn),
     &     x(maxm+maxn), pi(maxm)     , rc(maxm+maxn)
*     ------------------------------------------------------------------
*     USER workspace (none required)

      integer
     &     lenru, leniu, lencu
      parameter
     &     (lenru = 1,
     &      leniu = 1,
     &      lencu = 1)
      integer
     &     iu(leniu)
      double precision
     &     ru(lenru)
      character
     &     cu(lencu)*8
*     ------------------------------------------------------------------
*     SNOPT workspace

      integer
     &     lenrw, leniw, lencw
      parameter
     &     (lenrw = 600000,
     &      leniw = 350000,
     &      lencw =    500)
      integer
     &     iw(leniw)
      double precision
     &     rw(lenrw)
      character
     &     cw(lencw)*8
*     ------------------------------------------------------------------
      logical
     &     byname
      character
     &     lfile*20
      integer
     &     Errors, INFO, iObj, iSpecs, iPrint, iSumm, m,
     &     mincw, miniw, minrw, n, ne, nInf,
     &     nnCon, nnObj, nnJac, nOut, nS

      double precision
     &     ObjAdd, sInf, Obj
      external
     &     CatCon, CatObj
*     ------------------------------------------------------------------
*     Specify some of the SNOPT files.
*     iSpecs  is the Specs file   (0 if none).
*     iPrint  is the Print file   (0 if none).
*     iSumm   is the Summary file (0 if none).
*     nOut    is an output file used here by the main program.

      iSpecs = 4
      iPrint = 9
      iSumm  = 6
      nOut   = 6

      byname = .true.

      if ( byname ) then

*        Unix and DOS systems.  Open the Specs and print files.

         lfile = 'catmixb.spc'
         open( iSpecs, file=lfile, status='OLD',     err=800 )

         lfile = 'catmixb.out'
         open( iPrint, file=lfile, status='UNKNOWN', err=800 )
      end if

*     ------------------------------------------------------------------
*     Set options to their default values.
*     ------------------------------------------------------------------
      call snInit
     &   ( iPrint, iSumm, cw, lencw, iw, leniw, rw, lenrw )

*     ------------------------------------------------------------------
*     Read a Specs file.  This must include "Nonlinear constraints nh"
*     for some integer nh.  This defines 2*nh nonlinear constraints.
*     ------------------------------------------------------------------
      call snSpec
     &   ( iSpecs, INFO, cw, lencw, iw, leniw, rw, lenrw )

      if (INFO .ne. 101  .and.  INFO .ne. 107) then
         stop
      end if

      Errors = 0

*     ------------------------------------------------------------------
*     Generate the problem data.
*     ------------------------------------------------------------------
      call catData
     &   ( maxm, maxn, maxne, Errors, ProbNm, iObj, ObjAdd,
     &     m, n, ne, nnCon, nnObj, nnJac,
     &     Acol, indA, locA, bl, bu, hs, x, pi,
     &     cw, lencw, iw, leniw, rw, lenrw )

      if (Errors .gt. 0) then
         stop
      end if

*     ------------------------------------------------------------------
*     Go for it, using a Cold start.
*     iobj   = 0 means there is no linear objective row in Acol(*).
*     Objadd = 0.0 means there is no constant to be added to the
*            objective.
*     hs     need not be set if a basis file is to be input.
*            Otherwise, each hs(1:n) should be 0, 1, 2, 3, 4, or 5.
*            The values are used by the Crash procedure
*            to choose an initial basis B.
*            If hs(j) = 0 or 1, column j is eligible for B.
*            If hs(j) = 2, column j is initially superbasic (not in B).
*            If hs(j) = 3, column j is eligible for B and is given
*                          preference over columns with hs(j) = 0 or 1.
*            If hs(j) = 4 or 5, column j is initially nonbasic.
*     ------------------------------------------------------------------
      i1 = 0
      i2 = 0

*     Sticky parameters REQUIRED for HOT starts
      call snSet
     &   ( 'Sticky parameters yes', i1, i2, INFO,
     &     cw, lencw, iw, leniw, rw, lenrw )

      call snSeti
     &   ( 'Major Iterations', 20, i1, i2, INFO,
     &     cw, lencw, iw, leniw, rw, lenrw )

      call snOptB
     &   ( 'Cold', m, n, ne, nName,
     &     nnCon, nnObj, nnJac,
     &     iObj, ObjAdd, ProbNm,
     &     CatCon, CatObj,
     &     Acol, indA, locA, bl, bu, Names,
     &     hs, x, pi, rc,
     &     INFO, mincw, miniw, minrw,
     &     nS, nInf, sInf, Obj,
     &     cu, lencu, iu, leniu, ru, lenru,
     &     cw, lencw, iw, leniw, rw, lenrw )

      call snSeti
     &   ( 'Major Iterations', 200, i1, i2, INFO,
     &     cw, lencw, iw, leniw, rw, lenrw )

      call snOptB
     &   ( 'Hot', m, n, ne, nName,
     &     nnCon, nnObj, nnJac,
     &     iObj, objAdd, ProbNm,
     &     CatCon, CatObj,
     &     Acol, indA, locA, bl, bu, Names,
     &     hs, x, pi, rc,
     &     INFO, mincw, miniw, minrw,
     &     nS, nInf, sInf, Obj,
     &     cw, lencw, iw, leniw, rw, lenrw,
     &     cw, lencw, iw, leniw, rw, lenrw )

      if (INFO .eq. 82 .or. INFO .eq. 83 .or. INFO .eq. 84) then
         go to 900
      end if

      write(nOut, *) ' '
      write(nOut, *) 'catmixb finished.'
      write(nOut, *) 'Input  errors =', Errors
      write(nOut, *) 'snOptB INFO   =', INFO
      write(nOut, *) 'nInf          =', nInf
      write(nOut, *) 'sInf          =', sInf
      if (iObj .gt. 0) then
         write(nOut, *)
     &               'Obj           =', ObjAdd + x(n+iObj) + Obj
      else
         write(nOut, *)
     &               'Obj           =', ObjAdd + Obj
      end if
      if (INFO .ge. 30) go to 900
      stop

*     ------------------------------------------------------------------
*     Error exit.
*     ------------------------------------------------------------------
  800 write(nOut, 4000) 'Error while opening file', lfile
      stop

  900 write(nOut, *) ' '
      write(nOut, *) 'STOPPING because of error condition'
      stop

 4000 format(/  a, 2x, a  )

      end ! program catmixb

*+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

      subroutine catData
     &   ( maxm, maxn, maxne, Errors, Prob, iObj, ObjAdd,
     &     m, n, ne, nnCon, nnObj, nnJac,
     &     Acol, indA, locA, bl, bu, hs, x, pi,
     &     cw, lencw, iw, leniw, rw, lenrw )

      implicit
     &     none
      integer
     &     Errors, iObj, lencw, leniw, lenrw, maxm, maxn, maxne, m,
     &     n, ne, nnCon, nnObj, nnJac, indA(maxne), hs(maxn+maxm),
     &     locA(maxn+1), iw(leniw)
      double precision
     &     ObjAdd, Acol(maxne), bl(maxn+maxm), bu(maxn+maxm),
     &     x(maxn+maxm), pi(maxm), rw(lenrw)
      character
     &     Prob*8, cw(lencw)*8

*     ==================================================================
*     catdat  generates data for the test problem catmix.
*     The AMPL model is:
*
*     param tf := 1;      # Final time
*     param nh;           # Number of subintervals
*     param x1_0;         # Initial condition for x1
*     param x2_0;         # Initial condition for x2
*
*     param alpha;        # smoothing parameter;
*
*     param h := tf/nh;
*
*     var u {0..nh} <= 1, >= 0;
*     var x1 {0..nh};
*     var x2 {0..nh};
*
*     minimize objective:  -1 + x1[nh] + x2[nh]
*                             + alpha*h*sum{i in 0..nh-1} (u[i+1] - u[i])^2 ;
*
*     subject to ode1 {i in 0..(nh-1)}:
*     x1[i+1] = x1[i] + (h/2)*(u[i]*(10*x2[i]-x1[i]) + u[i+1]*(10*x2[i+1]-x1[i+1]));
*
*     subject to ode2 {i in 0..(nh-1)}:
*     x2[i+1] = x2[i] + (h/2)*(u[i]*(x1[i]-10*x2[i]) - (1-u[i])*x2[i] +
*                              u[i+1]*(x1[i+1]-10*x2[i+1]) - (1-u[i+1])*x2[i+1]);
*
*     subject to ic1:
*     x1[0] = x1_0;
*
*     subject to ic2:
*     x2[0] = x2_0;
*
*     Data:
*     param nh := 800;
*     param x1_0 := 1;
*     param x2_0:= 0;
*     param alpha := 0.0;;
*
*     let {i in 0..nh}  u[i] := 0;
*     let {i in 0..nh} x1[i] := 1;
*     let {i in 0..nh} x2[i] := 0;
*
*
*     The SNOPT constraints take the form
*              c(x) + A*x - s = 0,
*     where the Jacobian for c(x) + Ax is stored in Acol(*), and any
*     terms coming from c(x) are in the TOP LEFT-HAND CORNER of Acol(*),
*     with dimensions  nnCon x nnJac.
*     Note that the right-hand side is zero.
*     s is a set of slack variables whose bounds contain any constants
*     that might have formed a right-hand side.
*
*     The objective function is
*             f(x) + d'x
*     where d would be row iobj of A (but there is no such row in
*     this example).  f(x) involves only the FIRST nnObj variables.
*
*     On entry,
*     maxm, maxn, maxne are upper limits on m, n, ne.
*
*     On exit,
*     Errors  is 0 if there is enough storage, 1 otherwise.
*     m       is the number of nonlinear and linear constraints.
*     n       is the number of variables.
*     ne      is the number of nonzeros in Acol(*).
*     nnCon   is the number of nonlinear constraints (they come first).
*     nnObj   is the number of nonlinear objective variables.
*     nnJac   is the number of nonlinear Jacobian variables.
*     Acol    is the constraint matrix (Jacobian), stored column-wise.
*     indA    is the list of row indices for each nonzero in Acol(*).
*     locA    is a set of pointers to the beginning of each column of a.
*     bl      is the lower bounds on x and s.
*     bu      is the upper bounds on x and s.
*     hs(1:n) is a set of initial states for each x  (0,1,2,3,4,5).
*     x (1:n) is a set of initial values for x.
*     pi(1:m) is a set of initial values for the dual variables pi.
*
*     On entry,
*     maxF, maxn are upper limits on nnCon and n.
*
*     On exit,
*     Errors  is 0 if there is enough storage, 1 otherwise.
*
*     15 Dec 2004: First version of catmixb.
*     08 Apr 2008: Acol initialized, as required in the documentation.
*     ==================================================================
      integer
     &     i, nOut, ju, jx1, jx2, nh, ode1, ode2
*     ------------------------------------------------------------------
      double precision   zero,             one
      parameter         (zero   = 0.0d+0,  one    = 1.0d+0)
      double precision   bplus,            bminus
      parameter         (bplus  = 1.0d+20, bminus = -bplus)
*     ------------------------------------------------------------------
      nOut = 6
*     ------------------------------------------------------------------
*     The following call fetches nh, the number of nonlinear constraints.
*     It is specified at runtime in the SPECS file.
*     ------------------------------------------------------------------
      Errors = 0
      call sngeti
     &   ( 'Problem number', nh, Errors,
     &     cw, lencw, iw, leniw, rw, lenrw )

*     Check if there is enough storage.

      if ( nh    .le.  1          .or.
     &     maxm  .lt.  2* nh + 1  .or.
     &     maxn  .lt.  3*(nh + 1) .or.
     &     maxne .lt. 10* nh         ) then
         write(nOut, *) 'Not enough storage to generate a problem ',
     &                  'with ', 2*nh, ' nonlinear constraints'
         Errors = 1
      end if

      if (Errors .ge. 1) go to 910

*     Write nh into the problem name.

      write(Prob, '(i8)') nh
      if      (nh .lt.  100) then
         Prob(1:6) = 'Catmix'
      else if (nh .lt. 1000) then
         Prob(1:5) = 'Catmi'
      else
         Prob(1:3) = 'Cat'
      end if

      write(nOut, *) 'Problem CATMIX.   nh =', nh

      n     = 3*(nh + 1)
      nnCon = 2* nh
      m     = 2* nh + 1         ! Includes objective row
      nnJac = n
!     nnObj = nh
      nnObj = nh + 1

*     ObjAdd is a constant to be added to the objective.

      ObjAdd = - one

*     The AMPL format variables are ordered as follows:
*     variables u:       1: nh+1
*     variables x1:   nh+2:2nh+2
*     variables x2:  2nh+2:3nh+2
*     jx1, jx2, ju are the pointers for the variables in x.

      ju   = 1                  ! points to start of u  in  x.
      jx1  = ju  + nh + 1       ! points to start of x1 in  x.
      jx2  = jx1 + nh + 1       ! points to start of x2 in  x.

      ode1 = 1                  ! points to ode1 constraints in F.
      ode2 = ode1 + nh          ! points to ode2 constraints in F.

      iObj = ode2 + nh          ! Objective row

      ne   = 0

*     u columns

      do i = 0, nh
         locA(ju+i) =   ne + 1

         if (i .gt. 0) then
            ne        = ne + 1
            indA(ne)  = i
            Acol(ne)  = zero
*           Acol(ne)  = - half*h*(ten*x(jx2+i) - x(jx1+i))
            ne        = ne  + 1
            indA(ne)  = i   + nh
            Acol(ne)  = zero
*           Acol(ne)  = - half*h*(x(jx1+i) - nine*x(jx2+i))
         end if

         if (i .lt. nh) then
            ne        = ne + 1
            indA(ne)  = i  + 1
            Acol(ne)  = zero
*           Acol(ne)  = - half*h*(ten*x(jx2+i) - x(jx1+i))
            ne        = ne + 1
            indA(ne)  = i  + 1 + nh
            Acol(ne)  = zero
*           Acol(ne)  = - half*h*(x(jx1+i) - nine*x(jx2+i))
         end if

         bl(ju+i)  =  zero
         bu(ju+i)  =  one
          x(ju+i)  =  zero
         hs(ju+i)  =  0
      end do

*     x1 columns

      do i = 0, nh
         locA(jx1+i) =  ne + 1

         if (i .gt. 0) then
            ne        = ne + 1
            indA(ne)  = i
            Acol(ne)  = zero
*           Acol(ne)  =    one + half*h*x(ju+i)
            ne        = ne + 1
            indA(ne)  = i  + nh
            Acol(ne)  = zero
*           Acol(ne)  =        - half*h*x(ju+i)
         end if

         if (i .lt. nh) then
            ne        = ne + 1
            indA(ne)  = i  + 1
            Acol(ne)  = zero
*           Acol(ne)  =   -one + half*h*x(ju+i)
            ne        = ne + 1
            indA(ne)  = i  + 1 + nh
            Acol(ne)  = zero
*           Acol(ne)  =        - half*h*x(ju+i)
         end if

         bl(jx1+i) =  bminus
         bu(jx1+i) =  bplus
         x (jx1+i) =  one
         hs(jx1+i) =  0
      end do

      ne        = ne + 1
      indA(ne)  = iObj
      Acol(ne)  = one

*     x2 columns

      do i = 0, nh
         locA(jx2+i) =  ne + 1

         if (i .gt. 0) then
            ne        = ne + 1
            indA(ne)  = i
            Acol(ne)  = zero
*           Acol(ne)  =        - five*h*x(ju+i)
            ne        = ne + 1
            indA(ne)  = i  + nh
            Acol(ne)  = zero
*           Acol(ne)  =   one  + half*h*(nine*x(ju+i)   + one)
         end if

         if (i .lt. nh) then
            ne        = ne + 1
            indA(ne)  = i  + 1
            Acol(ne)  = zero
*           Acol(ne)  =        - five*h*x(ju+i)
            ne        = ne + 1
            indA(ne)  = i  + 1 + nh
            Acol(ne)  = zero
*           Acol(ne)  = - one  + half*h*(nine*x(ju+i)   + one)
         end if

         bl(jx2+i) =  bminus
         bu(jx2+i) =  bplus
         x (jx2+i) =  zero
         hs(jx2+i) =  0
      end do

      ne        = ne + 1
      indA(ne)  = iObj
      Acol(ne)  = one

      locA(n+1) = ne + 1

*     ------------------------------------------------------------------
*     Initialize the bounds
*     ------------------------------------------------------------------

*     Fix the boundary conditions.

      bl(jx1) = one
      bu(jx1) = one
      x (jx1) = one

      bl(jx2) = zero
      bu(jx2) = zero
      x (jx2) = zero

*     Bounds on the nonlinear constraints (all equalities).

      do i = n+1, n+nnCon
         bl(i) = zero
         bu(i) = zero
      end do

      bl(n+m) = bminus          ! Free objective row
      bu(n+m) = bplus

*     Initialize the nonlinear pi's (required)

      do i = 1, nnCon
         pi(i) = zero
      end do

  910 return

      end ! subroutine catData

*+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

      subroutine CatCon
     &   ( mode, m, n, njac, x, f, g, nState,
     &     cu, lencu, iu, leniu, ru, lenru )

      implicit
     &     none
      integer
     &     lencu, leniu, lenru, mode, m, n, njac, nState,
     &     iu(leniu)
      double precision
     &     x(n), f(m), g(njac), ru(lenru)
      character
     &     cu(lencu)*8
*     ------------------------------------------------------------------
*     This is funcon for problem catmix.
*     ------------------------------------------------------------------
      integer
     &     i, jx1, jx2, ju, ne, nh, ode1, ode2
      double precision
     &     h, rnh
*     ------------------------------------------------------------------
      double precision   half,          one
      parameter         (half = 0.5d+0, one = 1.0d+0)
      double precision   five,          nine,          ten
      parameter         (five = 5.0d+0, nine = 9.0d+0, ten  =10.0d+0)
      double precision   tf
      parameter         (tf   = one)
*     ------------------------------------------------------------------
      if (      nState .eq. 1) then ! First
         write(6, '(/a)') ' Starting  catmixb_hot con'
      else  if (nState .ge. 2) then ! Last
         write(6, '(/a)') ' Finishing catmixb_hot con'
      end if

      nh     = n/3 - 1
      rnh    = nh
      h      = tf/rnh

*     The AMPL format variables are ordered as follows:
*     variables u:       1: nh+1
*     variables x1:   nh+2:2nh+2
*     variables x2:  2nh+3:3nh+3
*     jx1, jx2, ju are the pointers for the variables in x.

      ju   = 1                  ! points to start of u  in  x.
      jx1  = ju  + nh + 1       ! points to start of x1 in  x.
      jx2  = jx1 + nh + 1       ! points to start of x2 in  x.

      ode1 = 1                  ! points to ode1 constraints in f.
      ode2 = ode1 + nh          ! points to ode2 constraints in f.

      if (mode .eq. 0  .or.  mode .eq. 2) then
         do i = 0, nh-1
*           subject to ode1 {i in 0..(nh-1)}
            f(ode1+i) = x(jx1+i+1) - x(jx1+i)
     &           - half*h*(  x(ju+i)  *(ten*x(jx2+i)   - x(jx1+i))
     &           + x(ju+i+1)*(ten*x(jx2+i+1) - x(jx1+i+1)))
*           subject to ode2 {i in 0..(nh-1)}
            f(ode2+i) = x(jx2+i+1) - x(jx2+i)
     &                  - half*h*( x(ju+i)  *(x(jx1+i)   - ten*x(jx2+i))
     &                         - (one-x(ju+i))  *x(jx2+i)
     &                         + x(ju+i+1)*(x(jx1+i+1) - ten*x(jx2+i+1))
     &                         - (one-x(ju+i+1))*x(jx2+i+1))
         end do
      end if

      if (mode .ge. 1) then

         ne   = 0

*        u columns

         do i = 0, nh
            if (i .gt. 0) then
               ne    = ne + 1
               g(ne) = - half*h*(ten*x(jx2+i) - x(jx1+i))
               ne    = ne  + 1
               g(ne) = - half*h*(x(jx1+i) - nine*x(jx2+i))
            end if

            if (i .lt. nh) then
               ne    = ne + 1
               g(ne) = - half*h*(ten*x(jx2+i) - x(jx1+i))
               ne    = ne + 1
               g(ne) = - half*h*(x(jx1+i) - nine*x(jx2+i))
            end if
         end do

*        x1 columns

         do i = 0, nh
            if (i .gt. 0) then
               ne    = ne + 1
               g(ne) =    one + half*h*x(ju+i)
               ne    = ne + 1
               g(ne) =        - half*h*x(ju+i)
            end if

            if (i .lt. nh) then
               ne    = ne + 1
               g(ne) =   -one + half*h*x(ju+i)
               ne    = ne + 1
               g(ne) =        - half*h*x(ju+i)
            end if
         end do

*        x2 columns

         do i = 0, nh
            if (i .gt. 0) then
               ne    = ne + 1
               g(ne) =        - five*h*x(ju+i)
               ne    = ne + 1
               g(ne) =   one  + half*h*(nine*x(ju+i)   + one)
            end if

            if (i .lt. nh) then
               ne    = ne + 1
               g(ne) =        - five*h*x(ju+i)
               ne    = ne + 1
               g(ne) = - one  + half*h*(nine*x(ju+i)   + one)
            end if
         end do
      end if

      end ! subroutine CatCon

*+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

      subroutine CatObj
     &   ( mode, n, x, f, g, nState,
     &     cu, lencu, iu, leniu, ru, lenru )

      implicit
     &     none

      integer
     &     lencu, leniu, lenru, mode, n, nState, iu(leniu)
      double precision
     &     f, x(n), g(n), ru(lenru)
      character
     &     cu(lencu)*8
*     ------------------------------------------------------------------
*     This is funobj for problem Catmix  (an optimal control problem).
*     ------------------------------------------------------------------
      integer
     &     i, ju, neG, nh
      double precision
     &     alpha, fObj, gObj0, gObj1, h, rnh, ti
*     ------------------------------------------------------------------
      double precision   zero,          one
      parameter         (zero = 0.0d+0, one = 1.0d+0)
      double precision   two
      parameter         (two  = 2.0d+0)
      double precision   tf
      parameter         (tf   = one)
*     ------------------------------------------------------------------
      if (      nState .eq. 1) then ! First
         write(6, '(/a)') ' Starting  catmixb_hot obj'
      else  if (nState .ge. 2) then ! Last
         write(6, '(/a)') ' Finishing catmixb_hot obj'
      end if

      alpha  = zero

!     nh     = n                  ! Beware. n = nnObj = nh
      nh     = n - 1              ! Beware. n = nnObj = nh
      rnh    = nh
      h      = tf/rnh

*     The AMPL format variables are ordered as follows:
*     variables u:       1: nh+1
*     variables x1:   nh+2:2nh+2
*     variables x2:  2nh+3:3nh+3
*     jx1, jx2, ju are the pointers for the variables in x.

      ju   = 1                  ! points to start of u  in  x.

      fObj   = zero
      gObj0  = zero

      neg    = 0

      if (mode .eq. 0  .or.  mode .eq. 1 .or.  mode .eq. 2) then
         do i = 0, nh-1
            ti   = x(i+ju+1) - x(i+ju)
            fObj = fObj + alpha*h*ti**2

            if (mode .eq. 1  .or.  mode .eq. 2) then
               neg    = neg + 1
               gObj1  =  two*alpha*h*ti
               g(neg) =  gObj0 - gObj1
               gObj0  =  gObj1
            end if
         end do
         g(neg+1) = - gObj0
      end if

      if (mode .eq. 0  .or.  mode .eq. 2) then
         f = fObj
      end if

      end ! subroutine CatObj
