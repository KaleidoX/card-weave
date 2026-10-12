use card_weave_core::{AddressBook, ContactDirectory, Error};
use serde_json::{Value, json};

#[derive(Default)]
pub(crate) struct DirectoryState {
    revision: u64,
    snapshot: Option<ContactDirectory>,
    group: Option<String>,
}
impl DirectoryState {
    pub fn invalidate(&mut self) {
        self.snapshot = None;
    }
    pub fn page(
        &mut self,
        book: &mut AddressBook,
        group: Option<String>,
        revision: Option<u64>,
        offset: usize,
    ) -> Result<Value, Error> {
        if revision.is_none() {
            let snapshot = book.directory(group.as_deref())?;
            self.revision = self
                .revision
                .checked_add(1)
                .ok_or(Error::Invalid("directory revision exhausted"))?;
            self.snapshot = Some(snapshot);
            self.group = group.clone();
        } else if revision != Some(self.revision) || group != self.group {
            return Err(Error::EditStale);
        }
        let snapshot = self.snapshot.as_ref().ok_or(Error::EditStale)?;
        let end = offset.saturating_add(50).min(snapshot.entries.len());
        let entries = snapshot
            .entries
            .get(offset..end)
            .ok_or(Error::Invalid("directory offset"))?;
        Ok(
            json!({"revision":self.revision,"sections":snapshot.sections,"total":snapshot.entries.len(),"offset":offset,"entries":entries}),
        )
    }
}
