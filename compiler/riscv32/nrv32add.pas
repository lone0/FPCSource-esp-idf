{
    Copyright (c) 2000-2002 by Florian Klaempfl and Jonas Maebe

    Code generation for add nodes on the Risc-V32

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
unit nrv32add;

{$i fpcdefs.inc}

  interface

    uses
      node, ncgadd, aasmbase, nrvadd, cpubase,
      cgbase;

    type
      trv32addnode = class(trvaddnode)
      private
        procedure cmp64_le(left_reg, right_reg: TRegister64; unsigned: boolean);
        procedure cmp64_lt(left_reg, right_reg: TRegister64; unsigned: boolean);
      protected
        function use_generic_mul32to64: boolean; override;
        function first_addfloat: tnode; override;

        procedure second_cmp64bit; override;
      end;

  implementation

    uses
      globtype,systems,constexp,
      cutils,verbose,
      paramgr,procinfo,
      aasmtai,aasmdata,aasmcpu,defutil,
      ncal,nadd,ncnv,symconst,symdef,
      cgcpu,cgutils,
      cpupara,
      ncon,nset,
      hlcgobj, ncgutil,cgobj;

    const
      cmpops: array[boolean] of TOpCmp = (OC_LT,OC_B);

    procedure trv32addnode.cmp64_lt(left_reg, right_reg: TRegister64;unsigned: boolean);
      begin
        cg.a_cmp_reg_reg_label(current_asmdata.CurrAsmList,OS_INT,cmpops[unsigned],right_reg.reghi,left_reg.reghi,location.truelabel);
        cg.a_cmp_reg_reg_label(current_asmdata.CurrAsmList,OS_INT,OC_NE,left_reg.reghi,right_reg.reghi,location.falselabel);
        cg.a_cmp_reg_reg_label(current_asmdata.CurrAsmList,OS_INT,OC_B,right_reg.reglo,left_reg.reglo,location.truelabel);
        cg.a_jmp_always(current_asmdata.CurrAsmList,location.falselabel);
      end;


    procedure trv32addnode.cmp64_le(left_reg, right_reg: TRegister64;unsigned: boolean);
      begin
        cg.a_cmp_reg_reg_label(current_asmdata.CurrAsmList,OS_INT,cmpops[unsigned],left_reg.reghi,right_reg.reghi,location.falselabel);
        cg.a_cmp_reg_reg_label(current_asmdata.CurrAsmList,OS_INT,OC_NE,left_reg.reghi,right_reg.reghi,location.truelabel);
        cg.a_cmp_reg_reg_label(current_asmdata.CurrAsmList,OS_INT,OC_B,left_reg.reglo,right_reg.reglo,location.falselabel);
        cg.a_jmp_always(current_asmdata.CurrAsmList,location.truelabel);
      end;

    function trv32addnode.first_addfloat: tnode;
      var
        procname: string[31];
        calln: tnode;
      begin
        if (target_info.abi<>abi_riscv_ilp32f) or
           not (is_double(resultdef) or is_double(left.resultdef) or
                (assigned(right) and is_double(right.resultdef))) then
          exit(inherited first_addfloat);
        if not is_double(left.resultdef) then
          inserttypeconv(left,s64floattype);
        if assigned(right) and not is_double(right.resultdef) then
          inserttypeconv(right,s64floattype);

        case nodetype of
          addn: procname:='__ADDDF3';
          subn: procname:='__SUBDF3';
          muln: procname:='__MULDF3';
          slashn: procname:='__DIVDF3';
          equaln: procname:='__EQDF2';
          unequaln: procname:='__NEDF2';
          ltn: procname:='__LTDF2';
          lten: procname:='__LEDF2';
          gtn: procname:='__GTDF2';
          gten: procname:='__GEDF2';
          else
            internalerror(2026101704);
        end;
        calln:=ccallnode.createintern(procname,ccallparanode.create(right,ccallparanode.create(left,nil)));
        left:=nil;
        right:=nil;
        if nodetype in [addn,subn,muln,slashn] then
          result:=calln
        else
          result:=caddnode.create(nodetype,calln,cordconstnode.create(int64(0),s32inttype,false));
      end;


    function trv32addnode.use_generic_mul32to64: boolean;
      begin
        result:=true;
      end;

    procedure trv32addnode.second_cmp64bit;
      var
        truelabel,
        falselabel: tasmlabel;
        unsigned: boolean;
        left_reg,right_reg: TRegister64;
      begin
        current_asmdata.getjumplabel(truelabel);
        current_asmdata.getjumplabel(falselabel);
        location_reset_jump(location,truelabel,falselabel);

        pass_left_right;
        force_reg_left_right(true,true);

        unsigned:=not(is_signed(left.resultdef)) or
                  not(is_signed(right.resultdef));

        left_reg:=left.location.register64;
        if (right.location.loc=LOC_CONSTANT) then
          begin
            if lo(right.location.value64)=0 then
              right_reg.reglo:=NR_X0
            else
              begin
                right_reg.reglo:=cg.getintregister(current_asmdata.CurrAsmList,OS_INT);
                cg.a_load_const_reg(current_asmdata.CurrAsmList,OS_INT,lo(right.location.value64),right_reg.reglo);
              end;
            if hi(right.location.value64)=0 then
              right_reg.reghi:=NR_X0
            else
              begin
                right_reg.reghi:=cg.getintregister(current_asmdata.CurrAsmList,OS_INT);
                cg.a_load_const_reg(current_asmdata.CurrAsmList,OS_INT,hi(right.location.value64),right_reg.reghi);
              end;
          end
        else
          right_reg:=right.location.register64;

        case NodeType of
          equaln:
            begin
              cg.a_cmp_reg_reg_label(current_asmdata.CurrAsmList,OS_INT,OC_NE,left_reg.reghi,right_reg.reghi,location.falselabel);
              cg.a_cmp_reg_reg_label(current_asmdata.CurrAsmList,OS_INT,OC_NE,left_reg.reglo,right_reg.reglo,location.falselabel);
              cg.a_jmp_always(current_asmdata.CurrAsmList,location.truelabel);
            end;
          unequaln:
            begin
              cg.a_cmp_reg_reg_label(current_asmdata.CurrAsmList,OS_INT,OC_NE,left_reg.reghi,right_reg.reghi,location.truelabel);
              cg.a_cmp_reg_reg_label(current_asmdata.CurrAsmList,OS_INT,OC_NE,left_reg.reglo,right_reg.reglo,location.truelabel);
              cg.a_jmp_always(current_asmdata.CurrAsmList,location.falselabel);
            end;
        else
          if nf_swapped in flags then
            case NodeType of
              ltn:
                cmp64_lt(right_reg, left_reg,unsigned);
              lten:
                cmp64_le(right_reg, left_reg,unsigned);
              gtn:
                cmp64_lt(left_reg, right_reg,unsigned);
              gten:
                cmp64_le(left_reg, right_reg,unsigned);
              else
                internalerror(2019051034);
            end
          else
            case NodeType of
              ltn:
                cmp64_lt(left_reg, right_reg,unsigned);
              lten:
                cmp64_le(left_reg, right_reg,unsigned);
              gtn:
                cmp64_lt(right_reg, left_reg,unsigned);
              gten:
                cmp64_le(right_reg, left_reg,unsigned);
              else
                internalerror(2019051033);
            end;
        end;
      end;

begin
   caddnode:=trv32addnode;
end.
