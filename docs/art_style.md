# gameX — Art Style Guide

Visual reference for keeping assets consistent across the project.

## Pack principal

**Tiny Tiles** by odiurd ([itch.io](https://odiurd.itch.io/tiny-tiles)) — versión Free Pack.

- Licencia: uso personal y comercial permitido. No redistribuir el pack.
- PPU (Pixels Per Unit): **256**
- Formato: PNG con transparencia

## Perspectiva

- **Isométrica 2:1** (estilo Age of Empires / strategy cozy)
- Tiles de terreno: rombo **256×128 px**
- Personajes: sprite sheets horizontales, frames **80×80 px**
- Direcciones de animación: `walk_up` (run_upward) y `walk_down` (run_backward / run_downward)

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

| Animación   | Obligatoria | Notas                          |
|-------------|-------------|--------------------------------|
| `idle`      | Sí          | 4 frames, loop                 |
| `walk_up`   | Sí          | 8 frames, loop                 |
| `walk_down` | Sí          | 8 frames, loop                 |
| `attack`    | Fase 3+     | Por implementar                |

## Import settings en Godot

Para todos los PNG en `assets/`:

| Setting  | Valor    | Motivo                          |
|----------|----------|---------------------------------|
| Filter   | Linear   | Bordes suaves (soft pixel)      |
| Mipmaps  | Off      | 2D                              |
| Repeat   | Disabled | Sprites únicos                  |

Proyecto: `textures/canvas_textures/default_texture_filter=0` (Linear).

## Referencias visuales

- Tiny Tiles (pack activo)
- Age of Empires II (composición isométrica, profundidad)
- Moonlighter (pixel suave con sombreado)

## Checklist al añadir assets nuevos

1. ¿Misma perspectiva isométrica?
2. ¿Escala compatible (tile 256×128, personaje ~80 px alto)?
3. ¿Misma paleta / grosor de línea?
4. ¿Sprite sheet horizontal con frames del mismo tamaño?
5. ¿Licencia clara para uso en el proyecto?
