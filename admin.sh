#!/usr/bin/env bash
# Script para automatizar la creación de usuarios y grupos en GNU/Linux,

# Alumno: TISERA AGUILERA, Adriano Gabriel.
# Carrera: Ingeniería Informática
# Legajo: 59059
# Universidad de Mendoza

# Decidí incluir tanto CLI (command line interface) como TUI (text user interface) para que el script sea más versátil y fácil de usar.

# Verificar que el script se ejecute como root
if [[ $EUID -ne 0 ]]; then
  echo "Este script debe ejecutarse como root o con sudo." >&2
  exit 1
fi

# Función para recortar espacios en cadenas
trim() {
  local var="$*"
  var="${var#${var%%[![:space:]]*}}"
  var="${var%${var##*[![:space:]]}}"
  echo -n "$var"
}

# Función para crear varios grupos a partir de una cadena CSV
create_groups() {
  IFS=',' read -ra _grps <<< "$1"
  for g in "${_grps[@]}"; do
    g=$(trim "$g")
    [[ -z "$g" ]] && continue
    if ! getent group "$g" &>/dev/null; then
      echo "Creando grupo '$g'..."
      groupadd "$g"
    else
      echo "El grupo '$g' ya existe."
    fi
  done
}

# --- Modo CLI ---
cli_mode() {
  local user_arg="" group_arg="" list_flag=0

  # Parseo de argumentos
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        user_arg="$2"
        shift 2
        ;;
      --group)
        group_arg="$2"
        shift 2
        ;;
      --list)
        list_flag=1
        shift
        ;;
      *)
        echo "Uso:
--user \"nombre\"           Crear o modificar un usuario.
--group \"g1,g2,...\"       Crear grupos. (separados por comas)
--list                    Listar usuarios y sus grupos.
--tui                     Abrir la interfaz interactiva.

Ejemplos:
- Crear usuario llamado Mario: --user \"mario\"
- Crear grupos g1 y g2: --group \"g1,g2\"
- Crear usuario llamado Mario y añadirlo a los grupos g1 y g2: --user \"mario\" --group \"g1,g2\"
        " >&2
        exit 1
        ;;
    esac
  done

  # Si solo piden lista
  if [[ $list_flag -eq 1 ]]; then
    echo "Usuarios y sus grupos:"
    while read -r u; do
      grupos=$(id -nG "$u")
      echo "  $u: $grupos"
    done < <(getent passwd | awk -F: '$3 >= 1000 { print $1 }')
    exit 0
  fi

  # Crear grupos si se especificó
  if [[ -n "$group_arg" ]]; then
    create_groups "$group_arg"
  fi

  # Crear o modificar usuario si se especificó
  if [[ -n "$user_arg" ]]; then
    # Pedir contraseña
    while true; do
      read -s -p "Contraseña para '$user_arg': " pass1; echo
      read -s -p "Confirmar contraseña: " pass2; echo
      [[ "$pass1" == "$pass2" ]] && break
      echo "→ Las contraseñas no coinciden. Intenta de nuevo."
    done

    # Preparar CSV de grupos para usermod/useradd
    local grp_csv=""
    if [[ -n "$group_arg" ]]; then
      IFS=',' read -ra _grps2 <<< "$group_arg"
      for g in "${_grps2[@]}"; do
        g=$(trim "$g")
        [[ -n "$g" ]] && grp_csv+="$g,"
      done
      grp_csv=${grp_csv%,}
    fi

    if id "$user_arg" &>/dev/null; then
      echo "El usuario '$user_arg' ya existe."
      if [[ -n "$grp_csv" ]]; then
        echo "→ Añadiendo a grupos: $grp_csv"
        usermod -a -G "$grp_csv" "$user_arg"
      fi
    else
      echo "Creando usuario '$user_arg'..."
      if [[ -n "$grp_csv" ]]; then
        useradd -m -G "$grp_csv" "$user_arg"
        echo "→ Grupos asignados: $grp_csv"
      else
        useradd -m "$user_arg"
      fi
    fi

    # Aplicar contraseña
    echo "$user_arg:$pass1" | chpasswd
    echo "Operación completada para el usuario '$user_arg'."
  fi

  # Si nada se pidió
  if [[ -z "$user_arg" && -z "$group_arg" ]]; then
    echo "Uso:
--user \"nombre\"           Crear o modificar un usuario.
--group \"g1,g2,...\"       Crear grupos. (separados por comas)
--list                    Listar usuarios y sus grupos.
--tui                     Abrir la interfaz interactiva.

Ejemplos:
- Crear usuario llamado Mario: --user \"mario\"
- Crear grupos g1 y g2: --group \"g1,g2\"
- Crear usuario llamado Mario y añadirlo a los grupos g1 y g2: --user \"mario\" --group \"g1,g2\"
    " >&2
    exit 1
  fi

  exit 0
}

# --- Modo TUI ---

# Dibuja una caja con contenido centrado y padding
draw_box() {
  local -n arr=$1
  local pad=4 max=0 width i line len left right padding
  for line in "${arr[@]}"; do
    [[ "$line" == "__SEP__" ]] && continue
    (( ${#line} > max )) && max=${#line}
  done
  width=$((max + pad))
  printf '╭'; printf '─%.0s' $(seq 1 $((width+2))); printf '╮\n'
  for i in "${!arr[@]}"; do
    line="${arr[i]}"
    if [[ "$line" == "__SEP__" ]]; then
      printf '├'; printf '─%.0s' $(seq 1 $((width+2))); printf '┤\n'
    else
      len=${#line}
      if (( i == 0 )); then
        left=$(((width - len) / 2))
        right=$((width - len - left))
        printf '│ %*s%s%*s │\n' "$left" "" "$line" "$right" ""
      else
        padding=$((width - len))
        printf '│ %s%*s │\n' "$line" "$padding" ""
      fi
    fi
  done
  printf '╰'; printf '─%.0s' $(seq 1 $((width+2))); printf '╯\n'
}

# Menú interactivo con flechas y selección visual
menu() {
  local title="$1"; shift
  local options=("$@") selected=0 row col start_row
  tput civis
  IFS=';' read -sdR -p $'\e[6n' row col
  start_row=${row#*[}
  while true; do
    tput cup $start_row 0
    local lines=("$title" "__SEP__")
    for i in "${!options[@]}"; do
      if (( i == selected )); then
        lines+=("● ${options[i]}")
      else
        lines+=("  ${options[i]}")
      fi
    done
    draw_box lines
    IFS= read -rsn1 key
    [[ $key == $'\x1b' ]] && { read -rsn2 -t 0.1 rest; key+=$rest; }
    case $key in
      $'\x1b[A')  (( selected = (selected - 1 + ${#options[@]}) % ${#options[@]} ));;
      $'\x1b[B')  (( selected = (selected + 1) % ${#options[@]} ));;
      "")         tput cnorm; return $selected;;
    esac
  done
}

# Gestión de usuarios
gestion_usuarios() {
  while true; do
    clear
    menu "GESTIÓN DE USUARIOS" "Crear/Modificar Usuario" "Volver"
    choice=$?
    case $choice in
      0)
        read -p "Nombre de usuario: " usuar
        while true; do
          read -s -p "Contraseña: " pass1; echo
          read -s -p "Confirmar contraseña: " pass2; echo
          [[ "$pass1" == "$pass2" ]] && break
          echo "Las contraseñas no coinciden. Intenta de nuevo."
        done
        read -p "Grupos (separados por coma): " grupos_input
        IFS=',' read -ra tmp <<< "$grupos_input"
        lista_grupos=()
        for g in "${tmp[@]}"; do
          g_trim=$(trim "$g")
          [[ -n "$g_trim" ]] && lista_grupos+=("$g_trim")
        done
        for g in "${lista_grupos[@]}"; do
          if ! getent group "$g" &>/dev/null; then
            echo "Creando grupo '$g'..."
            groupadd "$g"
          fi
        done
        groups_csv=$(IFS=,; echo "${lista_grupos[*]}")
        if id "$usuar" &>/dev/null; then
          echo "El usuario '$usuar' existe: añadiendo a grupos..."
          usermod -a -G "$groups_csv" "$usuar"
        else
          echo "Creando usuario '$usuar' con grupos '$groups_csv'..."
          useradd -m -G "$groups_csv" "$usuar"
        fi
        echo "$usuar:$pass1" | chpasswd
        echo "Operación completada para '$usuar'."
        read -p "[ENTER] para continuar..."
        ;;
      1) break ;;
    esac
  done
}

# Gestión de grupos
gestion_grupos() {
  while true; do
    clear
    menu "GESTIÓN DE GRUPOS" "Crear/Modificar Grupo" "Volver"
    choice=$?
    case $choice in
      0)
        read -p "Nombre de grupo: " grp
        read -p "Usuarios a añadir (separados por coma): " us_input
        IFS=',' read -ra tmp <<< "$us_input"
        lista_usrs=()
        for u in "${tmp[@]}"; do
          u_trim=$(trim "$u")
          [[ -n "$u_trim" ]] && lista_usrs+=("$u_trim")
        done
        if ! getent group "$grp" &>/dev/null; then
          echo "Creando grupo '$grp'..."
          groupadd "$grp"
        else
          echo "El grupo '$grp' ya existe."
        fi
        for u in "${lista_usrs[@]}"; do
          if id "$u" &>/dev/null; then
            usermod -a -G "$grp" "$u"
            echo "Usuario '$u' añadido a '$grp'."
          else
            echo "Advertencia: el usuario '$u' no existe." >&2
          fi
        done
        read -p "[ENTER] para continuar..."
        ;;
      1) break ;;
    esac
  done
}

# Listar todos los usuarios y sus grupos
listar_todo() {
  clear
  local lines=("USUARIOS Y SUS GRUPOS" "__SEP__")
  while read -r u; do
    grupos=$(id -nG "$u")
    lines+=("$u: $grupos")
  done < <(getent passwd | awk -F: '$3 >= 1000 { print $1 }')
  draw_box lines
  read -p "[ENTER] para volver..."
}

# Ciclo principal TUI
tui_mode() {
  while true; do
    clear
    menu "GESTIÓN DE USUARIOS Y GRUPOS" \
         "Usuarios" \
         "Grupos" \
         "Listar usuarios y sus grupos" \
         "Salir"
    case $? in
      0) gestion_usuarios ;;
      1) gestion_grupos   ;;
      2) listar_todo      ;;
      3) echo "Saliendo..."; exit 0 ;;
    esac
  done
}

# --- Punto de entrada: elegir modo ---
if [[ "$1" == "--tui" || "$1" == "-tui" ]]; then
  tui_mode
else
  cli_mode "$@"
fi
