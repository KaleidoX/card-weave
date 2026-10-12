use crate::*;
use pinyin::ToPinyin;
use std::collections::BTreeMap;

#[derive(Default)]
pub(crate) struct NameIndex(BTreeMap<String, (String, String)>);
fn source(data: &ContactData) -> String {
    serde_json::json!([
        data.display_name,
        data.phonetic_family_name,
        data.phonetic_middle_name,
        data.phonetic_given_name
    ])
    .to_string()
}
fn sort_name(data: &ContactData) -> String {
    let phonetic = format!(
        "{}{}{}",
        data.phonetic_family_name, data.phonetic_middle_name, data.phonetic_given_name
    );
    let name = if phonetic.trim().is_empty() {
        data.display_name.trim()
    } else {
        phonetic.trim()
    };
    let mut result = String::new();
    for c in name.chars() {
        if let Some(pinyin) = c.to_pinyin() {
            result.push_str(pinyin.plain());
        } else {
            result.extend(c.to_lowercase());
        }
    }
    result
}
impl NameIndex {
    pub fn prepare(&mut self, id: &str, data: &ContactData) {
        let source = source(data);
        if self
            .0
            .get(id)
            .is_some_and(|(previous, _)| previous == &source)
        {
            return;
        }
        self.0.insert(id.into(), (source, sort_name(data)));
    }
    pub fn remove(&mut self, id: &str) {
        self.0.remove(id);
    }
    pub fn key(&self, id: &str) -> Result<&str> {
        self.0
            .get(id)
            .map(|(_, key)| key.as_str())
            .ok_or(Error::Invalid("name index requires rebuild"))
    }
}
impl AddressBook {
    /// Populate names at open/sync boundaries; browsing never transliterates.
    pub(crate) fn prepare_name_index(&mut self) -> Result<()> {
        let mut after = String::new();
        let mut live = std::collections::BTreeSet::new();
        loop {
            let rows = self.sdk.read(|r| {
                r.query(
                "SELECT id,display_name,document FROM contacts WHERE id>?1 ORDER BY id LIMIT 256",
                &[Value::Text(after.clone())],
            )
            })?;
            if rows.is_empty() {
                break;
            }
            for row in rows {
                let contact = decode(&row, false)?;
                after = contact.id.clone();
                live.insert(contact.id.clone());
                self.name_index.prepare(&contact.id, &contact.data);
            }
        }
        self.name_index.0.retain(|key, _| live.contains(key));
        Ok(())
    }
}
