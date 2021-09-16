create or replace package body GOTIN_IG as


  /** get_next_art_ig
      Obtiene el anterior/siguiente artículo del listado, teniendo en cuenta los filtros y ordenaciones del usuario.
      Devuelve el ID_ART anterior/siguiente.
  
      p_new_pos_art = 1 => siguiente artículo
                     -1 => artículo anterior
  
      20210108 GOtin
  */
  function get_next_art_ig(p_app_id in number, p_page_id in number, p_colname_pk in varchar2, p_table in varchar2, p_cur_id in number, p_new_pos in number) return number is
    v_query varchar2(32767);
    v_report_id number;
    v_view_id   number;
    v_region_id number;
    --L_CURRENT_REPORT  APEX_190200.WWV_FLOW_INTERACTIVE_GRID.T_CURRENT_REPORT; --APEX 19.2
  
    v_cur_pos number;
    v_id_art number;
    
    v_nls_sort varchar2(64);
    v_nls_comp varchar2(64);
    v_nls_sort_orig varchar2(64);
    v_nls_comp_orig varchar2(64);
  begin
    select nls_sort, nls_comp
      into v_nls_sort, v_nls_comp
      from apex_applications
     where application_id = p_app_id;
     
    select value 
      into v_nls_sort_orig
      from v$nls_parameters
     where parameter = 'NLS_SORT';
    
    select value 
      into v_nls_comp_orig
      from v$nls_parameters
     where parameter = 'NLS_COMP';
     
    select region_id
      into v_region_id
      from apex_appl_page_igs
     where application_id = p_app_id
       and page_id = p_page_id;
  
    --L_CURRENT_REPORT := APEX_190200.WWV_FLOW_INTERACTIVE_GRID.GET_CURRENT_REPORT ( P_REGION_ID => v_region_id ); --APEX 19.2
    v_report_id := APEX_IG.GET_LAST_VIEWED_REPORT_ID(p_page_id => p_page_id, p_region_id => v_region_id); --L_CURRENT_REPORT.ID;
  
    apex_debug.message(p_message => 'Current region id: '||v_region_id, p_force => false);
    apex_debug.message(p_message => 'Current report id: '||v_report_id, p_force => false);
  
    select view_id
      into v_view_id
      from apex_appl_page_ig_rpt_views
     where report_id = v_report_id
       and view_type_code = 'GRID';
  
    apex_debug.message(p_message => 'View id: '||v_view_id, p_force => false);
  
    v_cur_pos := get_current_pos_art_ig(p_app_id, p_page_id, p_colname_pk, p_table, p_cur_id);
    with
    filts as (
      select listagg(
        case
          when irf.type_code = 'COLUMN' then -- para los filtros a nivel de columna, construimos y agregamos cada uno de los filtros
            case when irf.is_case_sensitive = 'Y' then upper(rc.source_expression) else rc.source_expression end ||' '||
            decode(irf.operator,'EQ','=','C','LIKE','NC','NOT LIKE','S','LIKE','NS','NOT LIKE','NEQ','!=','N','IS NULL',
              'NN','IS NOT NULL','IN','IN','NIN','NOT IN','GT','>','GTE','>=','LT','<','LTE','<=',
              'BETWEEN','BETWEEN')||' '||
            case when irf.operator in ('IN','NIN') then '('''||replace(case when irf.is_case_sensitive = 'Y' then upper(nvl(love.return_value, irf.expression)) else nvl(love.return_value, irf.expression) end,',',''',''')||''')'
                else case when irf.operator = 'BETWEEN' then replace(upper(nvl(love.return_value, irf.expression)),'~',' AND ') --sin case sensitive porque son solo fechas y números
                    else case when irf.operator in ('N','NN') then case when irf.is_case_sensitive = 'Y' then upper(nvl(love.return_value, irf.expression)) else nvl(love.return_value, irf.expression) end 
                        else '''' || case when irf.operator in ('C','NC') then '%'||case when irf.is_case_sensitive = 'Y' then upper(nvl(love.return_value, irf.expression)) else nvl(love.return_value, irf.expression) end ||'%'
                            else case when irf.operator in ('S','NS') then case when irf.is_case_sensitive = 'Y' then upper(nvl(love.return_value, irf.expression)) else nvl(love.return_value, irf.expression) end ||'%'
                                else case when irf.is_case_sensitive = 'Y' then upper(nvl(love.return_value, irf.expression)) else nvl(love.return_value, irf.expression) end
                                end
                            end || ''''
                        end
                    end
                end
          when irf.type_code = 'ROW' then -- para los filtros a nivel de fila, se filtran todas las columnas visibles
           '('||(
          select listagg('instr( '|| case when irf.is_case_sensitive = 'Y' then 'upper("' end || rc.source_expression|| case when irf.is_case_sensitive = 'Y' then '")' end ||','|| case when irf.is_case_sensitive = 'Y' then 'upper(' end || ''''||irf.expression||'''' ||case when irf.is_case_sensitive = 'Y' then ')' end ||') > 0', ' or ') within group (order by rc.display_sequence)
              from apex_appl_page_ig_columns rc
             where rc.application_id = p_app_id and rc.page_id = p_page_id
               and rc.source_type_code = 'DB_COLUMN'
               and rc.data_type = 'VARCHAR2'
           )||')'
        end
        , ' AND ') within group (order by rc.display_sequence) filts
        from apex_appl_page_ig_rpt_filters irf
      left join apex_appl_page_ig_columns rc on irf.column_id = rc.column_id
      left join apex_application_lov_entries love on love.lov_id = rc.lov_id and love.display_value = irf.expression
       where report_id = v_report_id
         and is_enabled = 'Yes'
    ),
    ord as (
      select listagg(source_expression||' '||decode(sort_direction,'Ascending','ASC','Descending','DESC')||' NULLS '||sort_nulls,',') within group (order by sort_order) ord
        from apex_appl_page_ig_columns/*apex_190200.wwv_flow_region_columns*/ rc
      inner join apex_appl_page_ig_rpt_columns /*apex_190200.wwv_flow_ig_report_columns*/ irc on rc.column_id = irc.column_id
       where rc.application_id = p_app_id and rc.page_id = p_page_id
         and source_type_code = 'DB_COLUMN'
         and view_id = v_view_id
         and sort_order is not null
         --and irc.is_visible = 'Y'
    )
    select 'select '||p_colname_pk||' from (select '||p_colname_pk||', rownum rn from (select '||p_colname_pk||' from '||p_table||' '||nvl2(filts.filts, 'where '||filts.filts, null) || nvl2(ord.ord, ' order by '|| ord.ord, null)||')) where rn = '||(v_cur_pos + p_new_pos) into v_query
    from filts, ord;
  
    apex_debug.message('query next pos');
    apex_debug.message(v_query);
  
    if v_nls_sort is not null then
      execute immediate 'alter session set nls_sort = '''||v_nls_sort||'''';
    end if;
    if v_nls_comp is not null then
      execute immediate 'alter session set nls_comp = '''||v_nls_comp||'''';
    end if;
  
    execute immediate v_query into v_id_art;
    
    execute immediate 'alter session set nls_sort = '''||v_nls_sort_orig||'''';
    execute immediate 'alter session set nls_comp = '''||v_nls_comp_orig||'''';
    
    return v_id_art;
  end get_next_art_ig;
  
  /** get_current_pos_art_ig
      Devuelve la posición actual del artículo seleccionado en el listado, según los filtros y orden establecidos por el usuario.
  
      20210108 GOtin
  */
  function get_current_pos_art_ig(p_app_id in number, p_page_id in number, p_colname_pk in varchar2, p_table in varchar2, p_id in number) return number is
    v_query varchar2(32767);
    v_report_id number;
    v_view_id   number;
    v_region_id number;
    --L_CURRENT_REPORT  APEX_190200.WWV_FLOW_INTERACTIVE_GRID.T_CURRENT_REPORT;
  
    v_cur_pos number;
      
    v_nls_sort varchar2(64);
    v_nls_comp varchar2(64);
    v_nls_sort_orig varchar2(64);
    v_nls_comp_orig varchar2(64);
  begin
    select nls_sort, nls_comp
      into v_nls_sort, v_nls_comp
      from apex_applications
     where application_id = p_app_id;
    
    select value 
      into v_nls_sort_orig
      from v$nls_parameters
     where parameter = 'NLS_SORT';
    
    select value 
      into v_nls_comp_orig
      from v$nls_parameters
     where parameter = 'NLS_COMP';
  
    select region_id
      into v_region_id
      from apex_appl_page_igs
     where application_id = p_app_id
       and page_id = p_page_id;
  
    --L_CURRENT_REPORT := APEX_190200.WWV_FLOW_INTERACTIVE_GRID.GET_CURRENT_REPORT ( P_REGION_ID => v_region_id );
    v_report_id := APEX_IG.GET_LAST_VIEWED_REPORT_ID(p_page_id => p_page_id, p_region_id => v_region_id); --L_CURRENT_REPORT.ID;
  
    apex_debug.message(p_message => 'Current region id: '||v_region_id, p_force => false);
    apex_debug.message(p_message => 'Current report id: '||v_report_id, p_force => false);
  
  
    select view_id
      into v_view_id
      from apex_appl_page_ig_rpt_views
     where report_id = v_report_id
       and view_type_code = 'GRID';
  
    apex_debug.message(p_message => 'View id: '||v_view_id, p_force => false);
  
    with
    filts as (
      select listagg(
        case
          when irf.type_code = 'COLUMN' then -- para los filtros a nivel de columna, construimos y agregamos cada uno de los filtros
            case when irf.is_case_sensitive = 'Y' then upper(rc.source_expression) else rc.source_expression end ||' '||
            decode(irf.operator,'EQ','=','C','LIKE','NC','NOT LIKE','S','LIKE','NS','NOT LIKE','NEQ','!=','N','IS NULL',
              'NN','IS NOT NULL','IN','IN','NIN','NOT IN','GT','>','GTE','>=','LT','<','LTE','<=',
              'BETWEEN','BETWEEN')||' '||
            case when irf.operator in ('IN','NIN') then '('''||replace(case when irf.is_case_sensitive = 'Y' then upper(nvl(love.return_value, irf.expression)) else nvl(love.return_value, irf.expression) end,',',''',''')||''')'
                else case when irf.operator = 'BETWEEN' then replace(upper(nvl(love.return_value, irf.expression)),'~',' AND ') --sin case sensitive porque son solo fechas y números
                    else case when irf.operator in ('N','NN') then case when irf.is_case_sensitive = 'Y' then upper(nvl(love.return_value, irf.expression)) else nvl(love.return_value, irf.expression) end 
                        else '''' || case when irf.operator in ('C','NC') then '%'||case when irf.is_case_sensitive = 'Y' then upper(nvl(love.return_value, irf.expression)) else nvl(love.return_value, irf.expression) end ||'%'
                            else case when irf.operator in ('S','NS') then case when irf.is_case_sensitive = 'Y' then upper(nvl(love.return_value, irf.expression)) else nvl(love.return_value, irf.expression) end ||'%'
                                else case when irf.is_case_sensitive = 'Y' then upper(nvl(love.return_value, irf.expression)) else nvl(love.return_value, irf.expression) end
                                end
                            end || ''''
                        end
                    end
                end
          when irf.type_code = 'ROW' then -- para los filtros a nivel de fila, se filtran todas las columnas visibles
           '('||(
          select listagg('instr( '|| case when irf.is_case_sensitive = 'Y' then 'upper("' end || rc.source_expression|| case when irf.is_case_sensitive = 'Y' then '")' end ||','|| case when irf.is_case_sensitive = 'Y' then 'upper(' end || ''''||irf.expression||'''' ||case when irf.is_case_sensitive = 'Y' then ')' end ||') > 0', ' or ') within group (order by rc.display_sequence)
              from apex_appl_page_ig_columns rc
             where rc.application_id = p_app_id and rc.page_id = p_page_id
               and rc.source_type_code = 'DB_COLUMN'
               and rc.data_type = 'VARCHAR2'
           )||')'
        end
        , ' AND ') within group (order by rc.display_sequence) filts
        from apex_appl_page_ig_rpt_filters irf
      left join apex_appl_page_ig_columns rc on irf.column_id = rc.column_id
      left join apex_application_lov_entries love on love.lov_id = rc.lov_id and love.display_value = irf.expression
       where report_id = v_report_id
         and is_enabled = 'Yes'
    ),
    ord as (
      select listagg(source_expression||' '||decode(sort_direction,'Ascending','ASC','Descending','DESC')||' NULLS '||sort_nulls,',') within group (order by sort_order) ord
        from apex_appl_page_ig_columns/*apex_190200.wwv_flow_region_columns*/ rc
      inner join apex_appl_page_ig_rpt_columns /*apex_190200.wwv_flow_ig_report_columns*/ irc on rc.column_id = irc.column_id
       where rc.application_id = p_app_id and rc.page_id = p_page_id
         and source_type_code = 'DB_COLUMN'
         and view_id = v_view_id
         and sort_order is not null
         --and irc.is_visible = 'Y'
    )
    select 'select rn from (select '||p_colname_pk||', rownum rn  from (select '||p_colname_pk||' from '||p_table||' '||nvl2(filts.filts, 'where '||filts.filts, null) || nvl2(ord.ord, ' order by '|| ord.ord, null)||')) where '||p_colname_pk||' = '||p_id into v_query
    from filts, ord;
  
    apex_debug.message('query current pos: ');
    apex_debug.message(v_query);
  
    if v_nls_sort is not null then
      execute immediate 'alter session set nls_sort = '''||v_nls_sort||'''';
    end if;
    if v_nls_comp is not null then
      execute immediate 'alter session set nls_comp = '''||v_nls_comp||'''';
    end if;
  
    execute immediate v_query into v_cur_pos;
    
    execute immediate 'alter session set nls_sort = '''||v_nls_sort_orig||'''';
    execute immediate 'alter session set nls_comp = '''||v_nls_comp_orig||'''';
    
    return v_cur_pos;
  end get_current_pos_art_ig;
end GOTIN_IG;
