//! export-pack: turns a folder in SimGolf's file layout into a simgolf asset pack (a GMod addon folder, also read by LÖVE).
//!
//!   export-pack <source> <out> [--id free] [--name "Free"] [--license GPL-2.0-or-later] [--water-one-look]
//!
//! <source> is either OpenSGolf's free base set (`sgtool freeset <dir>`: gfx/, sfx/, text/) or an original SimGolf install
//! (Data/, Flics/, Sounds/, SimsFX/). Names are matched case-insensitively.
//!
//! Output, with <id> the pack id:
//!   materials/simgolf/<id>/terrain/<theme>.png        one 2048 x 2048 atlas of the theme's 64 x 64 ground textures
//!   materials/simgolf/<id>/terrain/<theme>/<name>.png  the theme's path and wall overlays (TGA)
//!   materials/simgolf/<id>/sprites/<folder>/<name>.png one sheet per FLC sprite: a row per view, a column per frame
//!   sound/simgolf/<id>/<folder>/.../<name>.ogg|mp3|wav  OGG and MP3 copied as they are, other sounds as PCM WAV
//!   lua/simgolf/packs/<id>/*.lua                       the manifest: info, terrain, sounds, sprites/<folder>
//!
//! All output names are lower case, so lookups behave the same on Windows and Linux.

use sg_core::assets::{decode_bmp, decode_sound, decode_tga, Indexed, Rgba};
use sg_core::flc::decode_flc;
use sg_core::png::encode_png;
use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

const GAME: &str = "simgolf";
const THEMES: [&str; 4] = ["Parkland", "Desert", "Tropical", "Links"];

// terrain atlas: 64 x 64 textures in 66 x 66 cells (a pixel of each edge repeated round it, so filtering never takes the
// neighbour's colours), 31 x 31 cells in a 2048 x 2048 picture
const TEX: u32 = 64;
const CELL: u32 = 66;
const ATLAS: u32 = 2048;
const ATLAS_COLS: u32 = ATLAS / CELL;

// sprite sheets wrap their frames so no sheet is wider than this
const MAX_SHEET: u32 = 4096;

// largest manifest file before it is split
const MAX_MANIFEST: usize = 40_000;

struct Args {
    src: PathBuf,
    out: PathBuf,
    id: String,
    name: String,
    license: String,
    water_one_look: bool,
}

fn parse_args() -> Result<Args, String> {
    let mut pos = Vec::new();
    let (mut id, mut name, mut license) = ("free".to_string(), String::new(), "GPL-2.0-or-later".to_string());
    let mut water_one_look = false;
    let mut it = std::env::args().skip(1);
    while let Some(a) = it.next() {
        match a.as_str() {
            "--id" => id = it.next().ok_or("--id needs a value")?,
            "--name" => name = it.next().ok_or("--name needs a value")?,
            "--license" => license = it.next().ok_or("--license needs a value")?,
            "--water-one-look" => water_one_look = true,
            _ => pos.push(a),
        }
    }
    if pos.len() != 2 {
        return Err("usage: export-pack <source> <out> [--id free] [--name NAME] [--license LICENSE] [--water-one-look]".into());
    }
    if !id.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_') {
        return Err("--id may only use a-z, 0-9 and _".into());
    }
    if name.is_empty() {
        name = id.clone();
    }
    Ok(Args { src: pos[0].clone().into(), out: pos[1].clone().into(), id, name, license, water_one_look })
}

// ------------------------------------------------------------------------------------------------ files

fn child_ci(dir: &Path, name: &str) -> Option<PathBuf> {
    let want = name.to_lowercase();
    fs::read_dir(dir).ok()?.flatten().map(|e| e.path()).find(|p| {
        p.file_name().map(|n| n.to_string_lossy().to_lowercase() == want).unwrap_or(false)
    })
}

/// `rel` under the source, also under its gfx/, sfx/ or text/ folder (the free set's layout), case-insensitively.
fn resolve(src: &Path, rel: &[&str]) -> Option<PathBuf> {
    let mut roots = vec![src.to_path_buf()];
    for sub in ["gfx", "sfx", "text"] {
        if let Some(p) = child_ci(src, sub) {
            roots.push(p);
        }
    }
    'root: for root in roots {
        let mut p = root;
        for part in rel {
            match child_ci(&p, part) {
                Some(next) => p = next,
                None => continue 'root,
            }
        }
        return Some(p);
    }
    None
}

fn files_in(dir: &Path) -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = fs::read_dir(dir).map(|r| r.flatten().map(|e| e.path()).filter(|p| p.is_file()).collect()).unwrap_or_default();
    v.sort_by_key(|p| p.file_name().map(|n| n.to_string_lossy().to_lowercase()));
    v
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    let mut items: Vec<PathBuf> = rd.flatten().map(|e| e.path()).collect();
    items.sort();
    for p in items {
        if p.is_dir() {
            walk(&p, out);
        } else {
            out.push(p);
        }
    }
}

fn ext(p: &Path) -> String {
    p.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default()
}

fn stem_lower(p: &Path) -> String {
    p.file_stem().map(|s| s.to_string_lossy().to_lowercase()).unwrap_or_default()
}

fn write(path: &Path, bytes: &[u8]) {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).expect("create output folder");
    }
    fs::write(path, bytes).unwrap_or_else(|e| panic!("write {}: {e}", path.display()));
}

fn write_png(path: &Path, img: &Rgba) {
    write(path, &encode_png(img).expect("encode png"));
}

/// A Lua string literal.
fn lua_str(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            c if (c as u32) < 32 => {
                let _ = write!(o, "\\{}", c as u32);
            }
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

// ------------------------------------------------------------------------------------------------ terrain

fn parse_lighting(text: &str) -> Option<[[i32; 3]; 3]> {
    let grab = |tag: &str| -> Option<[i32; 3]> {
        let p = text.find(tag)?;
        let v: Vec<i32> = text[p + tag.len()..].split_whitespace().take(3).map_while(|t| t.parse().ok()).collect();
        (v.len() == 3).then(|| [v[0], v[1], v[2]])
    };
    Some([grab("#AMBIENT")?, grab("#DIFFUSE")?, grab("#SPECULAR")?])
}

fn blit_cell(atlas: &mut Rgba, img: &Rgba, cell: u32) {
    let (cx, cy) = ((cell % ATLAS_COLS) * CELL, (cell / ATLAS_COLS) * CELL);
    for y in 0..CELL {
        for x in 0..CELL {
            // the texture's own pixel, its edge pixels repeated into the 1-pixel border
            let sx = (x as i32 - 1).clamp(0, img.w as i32 - 1) as u32;
            let sy = (y as i32 - 1).clamp(0, img.h as i32 - 1) as u32;
            let s = ((sy * img.w + sx) * 4) as usize;
            let d = (((cy + y) * atlas.w + cx + x) * 4) as usize;
            atlas.px[d..d + 4].copy_from_slice(&img.px[s..s + 4]);
        }
    }
}

fn export_terrain(a: &Args, lua: &mut String) -> usize {
    let mut count = 0;
    lua.push_str("-- Terrain atlas layout. Each theme's atlas (terrain/<theme>.lua) is 2048 x 2048 with 66 x 66 cells, 31 to a row;\n");
    lua.push_str("-- cell i holds a 64 x 64 texture at x = (i % 31) * 66 + 1, y = floor(i / 31) * 66 + 1.\n");
    lua.push_str("return { atlasSize = 2048, cell = 66, cols = 31, tex = 64 }\n");
    for theme in THEMES {
        let Some(dir) = resolve(&a.src, &["Data", "Textures", theme]) else {
            eprintln!("terrain: no {theme} textures");
            continue;
        };
        let lower = theme.to_lowercase();
        let mut atlas = Rgba::new(ATLAS, ATLAS);
        let mut names = Vec::new();
        let mut overlays = Vec::new();
        for f in files_in(&dir) {
            match ext(&f).as_str() {
                "bmp" => {
                    let Ok(img) = fs::read(&f).map_err(|e| e.to_string()).and_then(|d| decode_bmp(&d)) else {
                        eprintln!("terrain: cannot read {}", f.display());
                        continue;
                    };
                    if img.w != TEX || img.h != TEX {
                        // walls and the cliff's strata are other sizes: overlays
                        write_png(&a.out.join(format!("materials/{GAME}/{}/terrain/{lower}/{}.png", a.id, stem_lower(&f))), &img);
                        overlays.push(stem_lower(&f));
                        continue;
                    }
                    let cell = names.len() as u32;
                    if cell >= ATLAS_COLS * ATLAS_COLS {
                        eprintln!("terrain: {theme} atlas full, {} left out", f.display());
                        continue;
                    }
                    blit_cell(&mut atlas, &img, cell);
                    names.push(stem_lower(&f));
                }
                "tga" => {
                    if let Ok(img) = fs::read(&f).map_err(|e| e.to_string()).and_then(|d| decode_tga(&d)) {
                        write_png(&a.out.join(format!("materials/{GAME}/{}/terrain/{lower}/{}.png", a.id, stem_lower(&f))), &img);
                        overlays.push(stem_lower(&f));
                    }
                }
                _ => {}
            }
        }
        write_png(&a.out.join(format!("materials/{GAME}/{}/terrain/{lower}.png", a.id)), &atlas);
        count += names.len() + overlays.len();

        let light = resolve(&a.src, &[&format!("{theme}Lighting.txt")])
            .and_then(|p| fs::read(p).ok())
            .and_then(|d| parse_lighting(&String::from_utf8_lossy(&d)));

        let mut t = String::new();
        let lua = &mut t;
        lua.push_str("-- Terrain textures of one theme. names[i + 1] is the texture in atlas cell i (its file name in lower case without\n");
        lua.push_str("-- .bmp, e.g. \"fairwaya0001\"). lighting = { ambient, diffuse, specular } as 0..255 colours.\n");
        let _ = writeln!(lua, "return {{\n\t\t\tatlas = {},", lua_str(&format!("terrain/{lower}.png")));
        if let Some([am, di, sp]) = light {
            let _ = writeln!(
                lua,
                "\t\t\tlighting = {{ ambient = {{ {}, {}, {} }}, diffuse = {{ {}, {}, {} }}, specular = {{ {}, {}, {} }} }},",
                am[0], am[1], am[2], di[0], di[1], di[2], sp[0], sp[1], sp[2]
            );
        }
        lua.push_str("\t\t\tnames = {");
        for (i, n) in names.iter().enumerate() {
            if i % 8 == 0 {
                lua.push_str("\n\t\t\t\t");
            }
            let _ = write!(lua, "{}, ", lua_str(n));
        }
        lua.push_str("\n\t\t\t},\n\t\t\toverlays = {");
        for n in &overlays {
            let _ = write!(lua, " [{}] = {},", lua_str(n), lua_str(&format!("terrain/{lower}/{n}.png")));
        }
        lua.push_str(" },\n}\n");
        write(&a.out.join(format!("lua/{GAME}/packs/{}/terrain/{lower}.lua", a.id)), t.as_bytes());
    }
    count
}

// ------------------------------------------------------------------------------------------------ sprites

struct Sprite {
    file: String,
    w: u32,
    h: u32,
    views: u32,
    fpv: u32,
    frames: u32,
    cols: u32,
    ax: i32,
    ay: i32,
    ms: u32,
    mask: u32,
}

/// A frame in RGBA: index 255 is the key colour. Shadow sprites keep only their ramp (0xf8..0xfb), as black at the strength
/// the original's blit darkens the ground with (1/2, 3/8, 1/4, 1/8; docs/SPRITES.md in OpenSGolf).
fn frame_rgba(f: &Indexed, shadow: bool) -> Vec<u8> {
    let mut px = vec![0u8; (f.w * f.h * 4) as usize];
    for (i, &ix) in f.idx.iter().enumerate() {
        let o = i * 4;
        if shadow {
            let a = match ix {
                0xf8 => 128,
                0xf9 => 96,
                0xfa => 64,
                0xfb => 32,
                _ => 0,
            };
            px[o + 3] = a;
        } else if ix != 255 {
            let p = ix as usize * 3;
            px[o..o + 3].copy_from_slice(&f.pal[p..p + 3]);
            px[o + 3] = 255;
        }
    }
    px
}

fn export_sprite(a: &Args, path: &Path, key: &str) -> Option<Sprite> {
    let d = fs::read(path).ok()?;
    let flc = match decode_flc(&d) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("sprite: {}: {e}", path.display());
            return None;
        }
    };
    if flc.frames.is_empty() || flc.w == 0 || flc.h == 0 {
        return None;
    }
    let shadow = stem_lower(path).ends_with("shadow");
    let n = flc.frames.len() as u32;
    let (views, fpv) = if flc.has_ext && flc.views > 0 && flc.frames_per_view > 0 { (flc.views, flc.frames_per_view) } else { (1, n) };
    let (w, h) = (flc.w, flc.h);
    let cols = fpv.min((MAX_SHEET / w).max(1)).max(1);
    let rows = n.div_ceil(cols);
    let mut sheet = Rgba::new(cols * w, rows * h);
    for (i, f) in flc.frames.iter().enumerate() {
        let (fx, fy) = ((i as u32 % cols) * w, (i as u32 / cols) * h);
        let px = frame_rgba(f, shadow);
        for y in 0..h.min(f.h) {
            let s = (y * f.w * 4) as usize;
            let dst = (((fy + y) * sheet.w + fx) * 4) as usize;
            let len = (w.min(f.w) * 4) as usize;
            sheet.px[dst..dst + len].copy_from_slice(&px[s..s + len]);
        }
    }
    let file = format!("sprites/{key}.png");
    write_png(&a.out.join(format!("materials/{GAME}/{}/{file}", a.id)), &sheet);
    let (ax, ay) = if flc.has_ext { (240 - flc.crop_x as i32, 240 - flc.crop_y as i32) } else { (w as i32 / 2, h as i32) };
    Some(Sprite { file, w, h, views, fpv, frames: n, cols, ax, ay, ms: flc.frame_ms, mask: if flc.has_ext { flc.view_mask } else { 1 } })
}

fn export_sprites(a: &Args) -> usize {
    let Some(flics) = resolve(&a.src, &["Flics"]) else {
        eprintln!("sprites: no Flics folder");
        return 0;
    };
    let mut all = Vec::new();
    walk(&flics, &mut all);
    // folder (lower case) -> key -> sprite
    let mut by_folder: BTreeMap<String, BTreeMap<String, Sprite>> = BTreeMap::new();
    for p in all.iter().filter(|p| ext(p) == "flc") {
        let rel = p.strip_prefix(&flics).unwrap();
        let folder = rel.iter().next().map(|s| s.to_string_lossy().to_lowercase()).unwrap_or_default();
        let key = rel.with_extension("").to_string_lossy().replace('\\', "/").to_lowercase();
        if let Some(s) = export_sprite(a, p, &key) {
            by_folder.entry(if rel.components().count() > 1 { folder } else { "misc".into() }).or_default().insert(key, s);
        }
    }
    let mut count = 0;
    for (folder, sprites) in &by_folder {
        // files are kept under MAX_MANIFEST bytes (GMod sends each Lua file to clients on its own), split as folder_2.lua...
        let header = format!(
            "-- Sprites from Flics/{folder}. Sheet: frame f (0-based, view-major: f = view * fpv + frame) is at\n\
             -- column f % cols, row floor(f / cols), w x h each. ax, ay: the ground point inside a frame. ms: frame time.\n\
             -- mask: bit set per stored view. shadow: key of the matching shadow sprite (drawn first, black with alpha).\n\
             return {{\n"
        );
        let mut part = 1;
        let mut lua = header.clone();
        let flush = |lua: &mut String, part: &mut i32| {
            lua.push_str("}\n");
            let name = if *part == 1 { format!("{folder}.lua") } else { format!("{folder}_{part}.lua") };
            write(&a.out.join(format!("lua/{GAME}/packs/{}/sprites/{name}", a.id)), lua.as_bytes());
            *part += 1;
            *lua = header.clone();
        };
        for (key, s) in sprites {
            if lua.len() > MAX_MANIFEST {
                flush(&mut lua, &mut part);
            }
            let shadow_key = format!("{key}shadow");
            let shadow = if sprites.contains_key(&shadow_key) { format!(", shadow = {}", lua_str(&shadow_key)) } else { String::new() };
            let _ = writeln!(
                lua,
                "\t[{}] = {{ file = {}, w = {}, h = {}, views = {}, fpv = {}, frames = {}, cols = {}, ax = {}, ay = {}, ms = {}, mask = {}{} }},",
                lua_str(key), lua_str(&s.file), s.w, s.h, s.views, s.fpv, s.frames, s.cols, s.ax, s.ay, s.ms, s.mask, shadow
            );
            count += 1;
        }
        flush(&mut lua, &mut part);
    }
    count
}

// ------------------------------------------------------------------------------------------------ sounds

fn wav_bytes(channels: u16, bits: u16, rate: u32, pcm: &[u8]) -> Vec<u8> {
    let block = channels * bits / 8;
    let mut o = Vec::with_capacity(44 + pcm.len());
    o.extend_from_slice(b"RIFF");
    o.extend_from_slice(&(36 + pcm.len() as u32).to_le_bytes());
    o.extend_from_slice(b"WAVEfmt ");
    o.extend_from_slice(&16u32.to_le_bytes());
    o.extend_from_slice(&1u16.to_le_bytes());
    o.extend_from_slice(&channels.to_le_bytes());
    o.extend_from_slice(&rate.to_le_bytes());
    o.extend_from_slice(&(rate * block as u32).to_le_bytes());
    o.extend_from_slice(&block.to_le_bytes());
    o.extend_from_slice(&bits.to_le_bytes());
    o.extend_from_slice(b"data");
    o.extend_from_slice(&(pcm.len() as u32).to_le_bytes());
    o.extend_from_slice(pcm);
    o
}

fn export_sounds(a: &Args, lua: &mut String) -> usize {
    lua.push_str("-- Sounds: key (folder/name in lower case, no extension) -> file under sound/simgolf/<pack>/.\nreturn {\n");
    let mut count = 0;
    for top in ["Sounds", "SimsFX"] {
        let Some(dir) = resolve(&a.src, &[top]) else { continue };
        let mut all = Vec::new();
        walk(&dir, &mut all);
        for p in all {
            if !matches!(ext(&p).as_str(), "wav" | "ogg" | "mp3" | "mp2") {
                continue;
            }
            let Ok(d) = fs::read(&p) else { continue };
            let rel = p.strip_prefix(&dir).unwrap().with_extension("");
            let key = format!("{}/{}", top.to_lowercase(), rel.to_string_lossy().replace('\\', "/").to_lowercase());
            // OGG and MP3 play in both GMod and LÖVE as they are (and stay small); anything else becomes PCM WAV
            let (file, bytes) = if d.starts_with(b"OggS") {
                (format!("{key}.ogg"), d)
            } else if d.starts_with(b"ID3") || (d.len() > 1 && d[0] == 0xff && d[1] & 0xe0 == 0xe0) {
                (format!("{key}.mp3"), d)
            } else {
                match decode_sound(&d) {
                    Ok(w) if !w.pcm.is_empty() => (format!("{key}.wav"), wav_bytes(w.channels, w.bits, w.sample_rate, &w.pcm)),
                    Ok(_) => continue,
                    Err(e) => {
                        eprintln!("sound: {}: {e}", p.display());
                        continue;
                    }
                }
            };
            write(&a.out.join(format!("sound/{GAME}/{}/{file}", a.id)), &bytes);
            let _ = writeln!(lua, "\t[{}] = {},", lua_str(&key), lua_str(&file));
            count += 1;
        }
    }
    lua.push_str("}\n");
    count
}

// ------------------------------------------------------------------------------------------------ main

fn main() {
    let a = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };
    if !a.src.is_dir() {
        eprintln!("source folder not found: {}", a.src.display());
        std::process::exit(1);
    }
    let packs = a.out.join(format!("lua/{GAME}/packs/{}", a.id));

    let mut terrain = String::new();
    let nt = export_terrain(&a, &mut terrain);
    write(&packs.join("terrain.lua"), terrain.as_bytes());
    println!("terrain: {nt} textures");

    let ns = export_sprites(&a);
    println!("sprites: {ns}");

    let mut sounds = String::new();
    let nw = export_sounds(&a, &mut sounds);
    write(&packs.join("sounds.lua"), sounds.as_bytes());
    println!("sounds: {nw}");

    let info = format!(
        "-- Pack info, written by tools/export-pack.\n-- waterOneLook: all water depths share one look (OpenSGolf's free set), so only water's edge against land blends.\n\
         return {{\n\tid = {},\n\tname = {},\n\tlicense = {},\n\tapiVersion = 1,\n\twaterOneLook = {},\n}}\n",
        lua_str(&a.id),
        lua_str(&a.name),
        lua_str(&a.license),
        a.water_one_look
    );
    write(&packs.join("info.lua"), info.as_bytes());

    let addon = format!(
        "{{\n\t\"title\": {:?},\n\t\"type\": \"model\",\n\t\"tags\": [\"fun\"],\n\t\"ignore\": []\n}}\n",
        format!("SimGolf asset pack: {}", a.name)
    );
    write(&a.out.join("addon.json"), addon.as_bytes());
}
