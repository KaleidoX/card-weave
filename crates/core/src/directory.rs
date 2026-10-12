use crate::*;
use std::collections::BTreeSet;

#[derive(Clone, Debug, Serialize)]
pub struct DirectoryEntry {
    pub id: String,
    pub display_name: String,
    pub subtitle: String,
    pub has_conflict: bool,
}
#[derive(Debug, Serialize)]
pub struct DirectorySection {
    pub initial: String,
    pub offset: usize,
    pub count: usize,
}
pub struct ContactDirectory {
    pub entries: Vec<DirectoryEntry>,
    pub sections: Vec<DirectorySection>,
}
impl AddressBook {
    /// Rebuild a disposable, compact browsing snapshot; documents stay in SQLite.
    pub fn directory(&mut self, group: Option<&str>) -> Result<ContactDirectory> {
        let filter = self.contact_group_filter(group)?;
        let conflicts = self
            .sdk
            .list_conflicts()?
            .into_iter()
            .filter(|c| c.table == 1)
            .map(|c| c.key)
            .collect::<BTreeSet<_>>();
        let mut sorted = Vec::new();
        let mut after = String::new();
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
                let conflict = conflicts.contains(&contact.id);
                if !filter.matches(&contact.id, conflict) {
                    continue;
                }
                let key = self.name_index.key(&contact.id)?.to_owned();
                let first = key
                    .chars()
                    .next()
                    .filter(char::is_ascii_alphabetic)
                    .map(|c| c.to_ascii_uppercase())
                    .unwrap_or('#');
                let section = if first == '#' { '[' } else { first };
                let data = contact.data;
                let subtitle = data
                    .phones
                    .first()
                    .or_else(|| data.emails.first())
                    .map(|v| v.value.clone())
                    .unwrap_or(data.organization);
                sorted.push((
                    section,
                    key,
                    DirectoryEntry {
                        id: contact.id,
                        display_name: data.display_name,
                        subtitle,
                        has_conflict: conflict,
                    },
                ));
            }
        }
        sorted.sort_by(|a, b| (&a.0, &a.1, &a.2.id).cmp(&(&b.0, &b.1, &b.2.id)));
        let mut sections: Vec<DirectorySection> = Vec::new();
        let mut entries = Vec::with_capacity(sorted.len());
        for (section, _, entry) in sorted {
            let initial = if section == '[' {
                "#".into()
            } else {
                section.to_string()
            };
            if let Some(last) = sections.last_mut().filter(|last| last.initial == initial) {
                last.count += 1;
            } else {
                sections.push(DirectorySection {
                    initial,
                    offset: entries.len(),
                    count: 1,
                });
            }
            entries.push(entry);
        }
        Ok(ContactDirectory { entries, sections })
    }
}
