{
    Copyright (c) 1998-2002 by Florian Klaempfl

    Generate RiscV assembler for math nodes

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************
}
unit nrvmat;

{$I fpcdefs.inc}

  interface

    uses
      node,ncgmat;

    type
      trvunaryminusnode = class(tcgunaryminusnode)
        function pass_1: tnode; override;
        procedure second_float;override;
      end;

implementation

    uses
      globtype,
      verbose,
      nmat,
      cpubase,systems,
      aasmdata,aasmcpu,
      cgbase,cgobj,cgcpu,cgutils,
      symconst,symdef,
      hlcgobj,
      defutil,
      pass_2;


    function trvunaryminusnode.pass_1: tnode;
      begin
        result:=inherited pass_1;
        if assigned(left) and (left.resultdef.typ=floatdef) and ilp32f_soft_double(left.resultdef) then
          expectloc:=LOC_REGISTER;
      end;


    procedure trvunaryminusnode.second_float;
      begin
        if ilp32f_soft_double(left.resultdef) then
          begin
            secondpass(left);
            if not(left.location.loc in [LOC_CREGISTER,LOC_REGISTER]) then
              hlcg.location_force_reg(current_asmdata.CurrAsmList,left.location,left.resultdef,left.resultdef,false);
            location_reset(location,LOC_REGISTER,OS_64);
            location.register64.reglo:=cg.getintregister(current_asmdata.CurrAsmList,OS_32);
            location.register64.reghi:=cg.getintregister(current_asmdata.CurrAsmList,OS_32);
            cg.a_op_const_reg_reg(current_asmdata.CurrAsmList,OP_XOR,OS_32,tcgint($80000000),left.location.registerhi,location.registerhi);
            cg.a_load_reg_reg(current_asmdata.CurrAsmList,OS_32,OS_32,left.location.register64.reglo,location.register64.reglo);
            exit;
          end;

        secondpass(left);
        location_reset(location,LOC_FPUREGISTER,def_cgsize(resultdef));
        location.register:=hlcg.getregisterfordef(current_asmdata.CurrAsmList,resultdef);
        hlcg.location_force_fpureg(current_asmdata.CurrAsmList,left.location,left.resultdef,true);
        case tfloatdef(left.resultdef).floattype of
          s32real:
            current_asmdata.CurrAsmList.concat(taicpu.op_reg_reg(A_FNEG_S,location.register,left.location.register));
          s64real:
            current_asmdata.CurrAsmList.concat(taicpu.op_reg_reg(A_FNEG_D,location.register,left.location.register));
          s128real:
            current_asmdata.CurrAsmList.concat(taicpu.op_reg_reg(A_FNEG_Q,location.register,left.location.register));
          else
            Internalerror(2025010901);
        end;
        cg.maybe_check_for_fpu_exception(current_asmdata.CurrAsmList);
      end;


begin
  cunaryminusnode := trvunaryminusnode;
end.

