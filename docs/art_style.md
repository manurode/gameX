# Nightfall — Art Style Guide

Visual reference for keeping assets consistent across the project.

## Pack principal

**Mediterranean Coastal** (`assets/tilesets/mediterranean/`) — pack activo del juego.

- Edificios, personajes, terreno isométrico y decoración mediterránea (estuco blanco, tejados terracota, verdes y agua turquesa)
- PPU (Pixels Per Unit): **256**
- Formato: PNG con transparencia
- Iconos de UI de recursos: `assets/ui/icons/` (estilo Mediterranean Coastal, 256×256)

Legacy: **Tiny Tiles** by odiurd ([itch.io](https://odiurd.itch.io/tiny-tiles)) — Free Pack, conservado como referencia / UI.

## Perspectiva

- **Isométrica 2:1** (estilo Age of Empires / strategy cozy)
- Tiles de terreno: rombo **256×128 px**
- Personajes: sprite sheets horizontales, frames **80×80 px**
- Direcciones de animación: `walk_up` / `idle_back` (espalda, NE–NW), `walk_down` / `idle` (frente, SE–SW), `walk_side` / `idle_side` (perfil Este; Oeste con `flip_h`)

## Estilo visual

- Hand-drawn / storybook — líneas suaves, no pixel duro 16×16
- Colores cálidos: verdes hierba, marrones tierra, azules agua suaves
- Proporciones chibi/cute, cabeza visible, siluetas legibles
- **No mezclar** con otros packs (Kenney 16×16, top-down plano, etc.)

## Paleta base (referencia)

| Uso        | Color aprox. | Hex       |
|------------|--------------|-----------|
| Hierba     | Verde claro  | `#7EC850` |
| Tierra     | Marrón       | `#8B6914` |
| Agua       | Azul         | `#4A90D9` |
| Sombra     | Negro 25%    | `#00000040` |
| Selección  | Amarillo     | `#FFFF4D` |

## Convención de nombres

```
chr_{personaje}_{animacion}.png     → unidades
env_{categoria}_{variante}.png      → terreno / edificios
fx_{nombre}.png                     → efectos
```

Ejemplos:
- `chr_knight_run_upward.png`
- `env_grass_a.png`
- `env_trees_oaks.png`

## Animaciones requeridas por unidad

| Animación      | Obligatoria | Notas                                      |
|----------------|-------------|--------------------------------------------|
| `idle`         | Sí          | Frente, 4 frames, loop                     |
| `idle_back`    | Sí          | Espalda (NW/NE)                            |
| `idle_side`    | Sí          | Perfil derecha; izquierda con flip         |
| `walk_up`      | Sí          | 8 frames, espalda                          |
| `walk_down`    | Sí          | 8 frames, frente                           |
| `walk_side`    | Sí          | 8 frames, perfil                           |
| `attack_*`     | Combate     | `attack`, `attack_back`, `attack_side`     |
| `afk_*`        | Civiles     | Trabajo frente / espalda / lado            |

## Import settings en Godot

Para todos los PNG en `assets/`:

| Setting  | Valor    | Motivo                          |
|----------|----------|---------------------------------|
| Filter   | Linear   | Bordes suaves (soft pixel)      |
| Mipmaps  | Off      | 2D                              |
| Repeat   | Disabled | Sprites únicos                  |

Proyecto: `textures/canvas_textures/default_texture_filter=0` (Linear).

## Referencias visuales

- Mediterranean Coastal (pack activo)
- Age of Empires II (composición isométrica, profundidad)
- Tiny Tiles (legacy)

## Checklist al añadir assets nuevos

1. ¿Misma perspectiva isométrica?
2. ¿Escala compatible (tile 256×128, personaje ~80 px alto)?
3. ¿Misma paleta / grosor de línea?
4. ¿Sprite sheet horizontal con frames del mismo tamaño?
5. ¿Licencia clara para uso en el proyecto?
