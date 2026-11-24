# Bézierio: project rules

Developer notes: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Plans: [docs/ROADMAP.md](docs/ROADMAP.md).

- **Locale:** every key in `locale/en/Bezierio.cfg` has a `;` comment right above
  it saying which element it's for and what that element does, ending in
  `[unreviewed]` until a human has checked it. Add one for each new key, and mark
  it `[unreviewed]` again when an element's behaviour changes (see
  DEVELOPMENT.md, Locale). Don't change the actual contents of the locale, just add comments, only when creating a new on, give it content.
