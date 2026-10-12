use crate::*;

impl AddressBook {
    /// Copies resolved contacts into a fresh dataset without switching the active book.
    pub fn migrate_to(&mut self, destination: &Path) -> Result<Config> {
        if self.config.version != 1 || !self.status()?.settled {
            return Err(Error::Invalid("migration requires a settled legacy book"));
        }
        let mut target = Self::init_version(destination, None, 2, true)?;
        let pending = destination.join("migration.pending");
        let mut offset = 0;
        loop {
            let page = self.list("", 64, offset)?;
            let rows = page
                .iter()
                .map(|c| row(&c.id, &c.data))
                .collect::<Result<Vec<_>>>()?;
            target.sdk.write_transaction(|w| {
                for values in &rows {
                    w.execute("INSERT INTO contacts VALUES (?1,?2,?3)", values)?;
                }
                Ok(())
            })?;
            offset += page.len() as u32;
            if page.len() < 64 {
                break;
            }
        }
        target.prepare_name_index()?;
        let config = target.config.clone();
        target.close()?;
        let sdk = Sdk::open(
            destination.join("contacts.sqlite"),
            config.identity(),
            schema(2),
            Baseline::Reject,
        )?;
        let mut verified = Self {
            sdk,
            config: config.clone(),
            name_index: name_index::NameIndex::default(),
        };
        verified.prepare_name_index()?;
        let mut offset = 0;
        loop {
            let page = self.list("", 64, offset)?;
            for contact in &page {
                if verified.get(&contact.id)?.map(|c| c.data) != Some(contact.data.clone()) {
                    return Err(Error::Invalid("migration verification failed"));
                }
            }
            offset += page.len() as u32;
            if page.len() < 64 {
                break;
            }
        }
        verified.close()?;
        fs::remove_file(pending)?;
        #[cfg(unix)]
        fs::File::open(destination)?.sync_all()?;
        Ok(config)
    }
}
