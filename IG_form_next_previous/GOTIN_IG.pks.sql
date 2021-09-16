create or replace package GOTIN_IG as


  /** get_next_art_ig
      Obtiene el anterior/siguiente artículo del listado, teniendo en cuenta los filtros y ordenaciones del usuario.
      Devuelve el ID_ART anterior/siguiente.
  
      p_new_pos_art = 1 => siguiente artículo
                     -1 => artículo anterior
  
      20210108 GOtin
  */
  function get_next_art_ig(p_app_id     in number,
                           p_page_id    in number,
                           p_colname_pk in varchar2,
                           p_table      in varchar2,
                           p_cur_id     in number,
                           p_new_pos    in number) return number;

  /** get_current_pos_art_ig
      Devuelve la posición actual del artículo seleccionado en el listado, según los filtros y orden establecidos por el usuario.
  
      20210108 GOtin
  */
  function get_current_pos_art_ig(p_app_id     in number,
                                  p_page_id    in number,
                                  p_colname_pk in varchar2,
                                  p_table      in varchar2,
                                  p_id         in number) return number;
end;
