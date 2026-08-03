# avan

Puerto en [Zig](https://ziglang.org/) del núcleo de parsing de [Bukcraw](https://github.com/helvetios16/bukcraw) (mi scraper de Goodreads en TypeScript), escrito para aprender el lenguaje implementando algo con requisitos reales en vez de ejercicios de tutorial.

## Qué incluye

- **`http_client.zig`** — cliente HTTP mínimo sobre `std.http`.
- **`json_parser.zig`** — utilidades sobre el parser JSON de la stdlib para navegar la estructura `__NEXT_DATA__` que Goodreads embebe en sus páginas.
- **`blog_parser.zig`**, **`book_parser.zig`**, **`edition_parser.zig`** — extracción de blogs, libros y ediciones desde el HTML/JSON de Goodreads, cada uno con su archivo de tests (`*_test.zig`).
- **`file_client.zig`** — utilidades de I/O a disco (guardar HTML fetcheado, útil para debug sin volver a pegarle a la red).

## Por qué existe

No es una reescritura completa de Bukcraw ni busca reemplazarlo — Bukcraw sigue siendo el proyecto real, con toda la capa de CLI, base de datos y orquestación del pipeline. `avan` es el subconjunto de lógica de parsing reimplementado en un lenguaje de sistemas para entender manejo manual de memoria (`GeneralPurposeAllocator`), gestión de errores explícita y la ausencia de las comodidades que TypeScript da por sentadas (garbage collector, `JSON.parse`, tipos estructurales).

## Uso

```sh
zig build run
```

Requiere Zig `0.14.1` o superior (ver `build.zig.zon`).
