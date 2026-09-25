# KH PC Save Transfer

Use a **Kingdom Hearts HD 1.5+2.5 ReMIX** (or 2.8) PC save downloaded from someone else — e.g. a 100% save — on **your own Steam account**.

Without this, the game says *"The save data is corrupted and will be deleted"*, because each save container is tied to the account that created it.

One `.bat` file. Nothing to download or install: it only uses PowerShell and .NET, which ship with Windows 10/11.

[Español más abajo](#español)

## Usage

1. Start the game you want once from Steam (reach the title screen) and close it, so your own save container exists.
2. Close every Kingdom Hearts window, including the collection launcher.
3. **Drag the downloaded save** (`KHFM.png`, `KHIIFM.png`, `KHReCoM.png`, `KHBbSFM.png`, …) **onto `KH_Save_Transfer.bat`**.
   You can also double-click the `.bat` and paste the path.
4. Launch the game and pick *Load Game*. If Steam reports a cloud conflict, keep the **local** files.

The tool finds your Documents folder (OneDrive redirection included), your SteamID (from the save folder name) and the matching container automatically. If you have more than one Steam account it asks which one.

**Warning:** a container holds *all* save slots of that game. Your previous container is backed up to the `backups` folder next to the `.bat` before anything is written. To undo, copy the backup over the file shown as *Destination* and give it its original name back.

## What it does

The container is a PNG file whose `sqEX` chunk holds the saves. Only the first 256 bytes of that chunk depend on the account:

- they are XOR-ed with a 16-byte per-account key;
- once decrypted, the first 16 bytes must equal `MD5("<SteamID64>1")`.

The tool reads your key from your own container (`your row 0 XOR MD5("<SteamID64>1")`), reads the source key from the empty rows of the downloaded header, replaces the account check with yours, re-encrypts the header with your key and recomputes the PNG CRC. **The save data itself is never modified.**

Safety checks: it refuses to run while the game is open, checks that both files are the same game/size and that both headers decrypt to the expected layout, and makes a backup first.

## Compatibility

| Game | Status |
|---|---|
| Kingdom Hearts Final Mix (`KHFM`) | Tested: a 100% save loads on Steam |
| Kingdom Hearts II Final Mix (`KHIIFM`), Re:Chain of Memories (`KHReCoM`) | Same header scheme verified on Steam containers; save transfer not yet tested in game |
| Birth by Sleep (`KHBbSFM`), 2.8 / Dream Drop Distance (`KH3DHD`) | Should work (same format), untested |

Tested with the Steam release (September 2026). Saves from Epic Games or other Steam accounts should work the same way. Feedback welcome.

## Disclaimer

For single-player save files only. Not affiliated with Square Enix or Disney. Use at your own risk; keep your backups.

---

## Español

Permite usar en **tu cuenta de Steam** una partida de **Kingdom Hearts HD 1.5+2.5 ReMIX** (o 2.8) descargada de otra persona, por ejemplo un save al 100 %. Sin esto, el juego dice *"Los datos de guardado están dañados y se van a eliminar"*.

Un único `.bat`, sin descargar ni instalar nada.

1. Abre una vez desde Steam el juego que quieras (hasta la pantalla de título) y ciérralo.
2. Cierra todos los juegos de Kingdom Hearts y el launcher.
3. **Arrastra el save descargado** (`KHFM.png`, `KHIIFM.png`, …) **encima de `KH_Save_Transfer.bat`**.
4. Abre el juego y entra en *Cargar partida*. Si Steam avisa de un conflicto con la nube, elige los archivos **locales**.

Detecta solo la carpeta de Documentos, tu SteamID y el archivo correcto. Antes de escribir nada guarda una copia de tu contenedor en la carpeta `backups`. Para deshacerlo, copia esa copia sobre el archivo indicado como *Destination* y devuélvele su nombre original. Un contenedor incluye **todas** las ranuras de ese juego.

Funcionamiento: sólo cambia la cabecera de 256 bytes (XOR con una clave por cuenta y `MD5("<SteamID64>1")` como comprobación). Las partidas en sí no se tocan.
