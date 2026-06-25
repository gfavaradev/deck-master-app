/**
 * Sorgenti news per catalogo.
 *
 * Ogni entry: { catalog, type: "rss" | "html", url, sourceName, kind: "official" | "forum" }
 *
 * Cataloghi senza sorgente configurata vengono saltati da index.js (vedi ALL_CATALOGS).
 * Fase B (incrementale): aggiungere qui le fonti per pokemon/magic/onepiece/etc. dopo
 * aver verificato con WebFetch la struttura reale del sito/forum ufficiale — non
 * inventare selettori CSS senza averli osservati sulla pagina vera.
 */
export const SOURCES = [
  {
    catalog: "yugioh",
    type: "rss",
    url: "https://ygorganization.com/feed/",
    sourceName: "YGOrganization",
    kind: "official",
  },
  {
    catalog: "pokemon",
    type: "rss",
    url: "https://www.pokebeach.com/forums/forum/front-page-news.18/index.rss",
    sourceName: "PokéBeach",
    kind: "forum",
  },
  {
    catalog: "onepiece",
    type: "rss",
    url: "https://onepieceplayer.com/news/feed/",
    sourceName: "One Piece Player",
    kind: "community",
  },
  {
    catalog: "flesh-and-blood",
    type: "rss",
    url: "https://fabtcg.com/feed/",
    sourceName: "Flesh and Blood TCG (Legend Story Studios)",
    kind: "official",
  },
  {
    catalog: "riftbound",
    type: "rss",
    url: "https://riftbound.gg/feed/",
    sourceName: "Riftbound.gg",
    kind: "community",
  },
  {
    catalog: "digimon",
    type: "rss",
    url: "https://withthewill.net/forums/-/index.rss",
    sourceName: "With the Will (Digimon Forums)",
    kind: "forum",
  },
  {
    catalog: "vanguard",
    type: "rss",
    url: "https://en.bushiroad.com/feed/",
    sourceName: "Bushiroad (official)",
    kind: "official",
  },
];

// Cataloghi senza fonte verificata al momento (nessun feed RSS reale trovato):
// magic, lorcana, dragon-ball-super, star-wars, gundam, union-arena.
// Da ricontrollare periodicamente — Wizards/MTG ha disattivato gli RSS pubblici,
// gli altri publisher non espongono feed dedicati al gioco specifico.
