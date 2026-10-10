use card_weave_core::{
    AddressBook, Cancellation, ContactData, Error, MAX_DOCUMENT_BYTES, Resolution, Result,
    backend::Backend, read_bounded,
};
use serde_json::{Value, json};
use std::path::Path;

const HELP: &str = "card-weave HOME COMMAND [ARGS]\n\
  init [DATASET]                 create a NEW directory / join a dataset\n\
  info                           persistent dataset/device identity\n\
  create CONTACT.json            create a contact, return generated ID\n\
  get ID                         contact projection and any conflict\n\
  list [SEARCH [LIMIT [OFFSET]]]  page (default 100, max 500), plus conflicts\n\
  update ID CONTACT.json         replace a nonconflicted contact\n\
  delete ID                      delete a nonconflicted contact\n\
  conflicts                      full candidates including deletions\n\
  resolve ID RESOLUTION.json     observed version IDs + contact or null\n\
  status                         local sync and conflict state\n\
  sync BACKEND.json              one bounded synchronization pass\n\
All commands emit JSON. Exit: 0 success, 2 input/not-found, 3 conflict,\n\
4 storage/network/SDK failure, 5 sync incomplete or conflicts remain.\n\
Credentials are explicit environment variables referenced by BACKEND.json.";
fn args_len(args: &[String], min: usize, max: usize) -> Result<()> {
    if !(min..=max).contains(&args.len()) {
        return Err(Error::Invalid("wrong arguments; use --help"));
    }
    Ok(())
}
fn contact(path: &str) -> Result<ContactData> {
    ContactData::from_json(&read_bounded(Path::new(path), MAX_DOCUMENT_BYTES)?)
}
fn number(text: Option<&String>, default: u32) -> Result<u32> {
    text.map(|s| {
        s.parse()
            .map_err(|_| Error::Invalid("invalid pagination integer"))
    })
    .unwrap_or(Ok(default))
}
async fn run(args: Vec<String>) -> Result<(Value, u8)> {
    if args.len() == 1 && matches!(args[0].as_str(), "--help" | "-h") {
        return Ok((json!({"help": HELP}), 0));
    }
    args_len(&args, 2, 5)?;
    let home = Path::new(&args[0]);
    let command = args[1].as_str();
    let tail = &args[2..];
    if command == "init" {
        args_len(tail, 0, 1)?;
        let mut book = AddressBook::init(home, tail.first().cloned())?;
        let result = json!(book.config());
        book.close()?;
        return Ok((result, 0));
    }
    let mut book = AddressBook::open(home)?;
    let mut exit = 0;
    let value = match command {
        "info" => {
            args_len(tail, 0, 0)?;
            json!(book.config())
        }
        "create" => {
            args_len(tail, 1, 1)?;
            json!(book.create(contact(&tail[0])?)?)
        }
        "get" => {
            args_len(tail, 1, 1)?;
            let contact = book.get(&tail[0])?;
            let conflict = book.conflicts()?.into_iter().find(|c| c.id == tail[0]);
            if contact.is_none() && conflict.is_none() {
                return Err(Error::NotFound);
            }
            json!({"contact": contact, "conflict": conflict})
        }
        "list" => {
            args_len(tail, 0, 3)?;
            json!({"contacts": book.list(tail.first().map(String::as_str).unwrap_or(""), number(tail.get(1),100)?, number(tail.get(2),0)?)?, "conflicts": book.conflicts()?})
        }
        "update" => {
            args_len(tail, 2, 2)?;
            json!(book.update(&tail[0], contact(&tail[1])?)?)
        }
        "delete" => {
            args_len(tail, 1, 1)?;
            book.delete(&tail[0])?;
            json!({"deleted": tail[0]})
        }
        "conflicts" => {
            args_len(tail, 0, 0)?;
            json!(book.conflicts()?)
        }
        "resolve" => {
            args_len(tail, 2, 2)?;
            let resolution: Resolution =
                serde_json::from_slice(&read_bounded(Path::new(&tail[1]), 512 * 1024)?)?;
            book.resolve(&tail[0], resolution)?;
            json!({"resolved": tail[0], "status": book.status()?})
        }
        "status" => {
            args_len(tail, 0, 0)?;
            json!(book.status()?)
        }
        "sync" => {
            args_len(tail, 1, 1)?;
            let backend: Backend =
                serde_json::from_slice(&read_bounded(Path::new(&tail[0]), 16384)?)?;
            let transport = backend.connect()?;
            let outcome = book.sync(&transport, &Cancellation::default()).await?;
            if !outcome.status.settled {
                exit = 5;
            }
            json!(outcome)
        }
        _ => return Err(Error::Invalid("unknown command; use --help")),
    };
    book.close()?;
    Ok((value, exit))
}
#[tokio::main]
async fn main() -> std::process::ExitCode {
    match run(std::env::args().skip(1).collect()).await {
        Ok((value, exit)) => {
            println!("{}", json!({"ok": true, "result": value}));
            std::process::ExitCode::from(exit)
        }
        Err(error) => {
            let exit = match error.code() {
                "invalid_input" | "not_found" => 2,
                "conflict_requires_resolution" => 3,
                _ => 4,
            };
            eprintln!(
                "{}",
                json!({"ok": false, "error": {"code": error.code(), "message": error.to_string()}})
            );
            std::process::ExitCode::from(exit)
        }
    }
}
