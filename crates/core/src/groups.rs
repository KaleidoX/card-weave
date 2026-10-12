use crate::*;
use serde_json::{Value as Json, json};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MembershipChange {
    pub contact_id: String,
    pub expected: Option<String>,
    pub joined: bool,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GroupMembershipChange {
    pub group_id: String,
    pub expected: Option<String>,
    pub joined: bool,
}
#[derive(Debug, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub enum GroupCommand {
    ContactGroups {
        id: String,
    },
    SetContactGroups {
        id: String,
        changes: Vec<GroupMembershipChange>,
    },
    List,
    Create {
        name: String,
    },
    Rename {
        id: String,
        expected: String,
        name: String,
    },
    Delete {
        id: String,
        expected: String,
    },
    Members {
        id: String,
    },
    SetMembers {
        id: String,
        changes: Vec<MembershipChange>,
    },
    Contacts {
        group: Option<String>,
        search: String,
        offset: u32,
    },
    Conflicts,
    Resolve {
        table: u32,
        id: String,
        observed: Vec<VersionId>,
        #[serde(deserialize_with = "Option::deserialize")]
        value: Option<String>,
    },
}
fn strings(row: &[Value]) -> Result<Vec<String>> {
    row.iter()
        .map(|v| {
            if let Value::Text(s) = v {
                Ok(s.clone())
            } else {
                Err(Error::Invalid("invalid entity row"))
            }
        })
        .collect()
}
fn group_name(name: &str) -> Result<String> {
    let name = name.trim();
    if name.is_empty() || name.len() > 128 || name.contains('\0') {
        return Err(Error::Invalid("group name bounds"));
    }
    Ok(name.into())
}
fn group_row(id: &str, name: &str) -> Vec<Value> {
    vec![
        Value::Text(id.into()),
        Value::Text(name.into()),
        Value::Text(json!({"version":1,"name":name}).to_string()),
    ]
}
impl AddressBook {
    fn require_groups(&self) -> Result<()> {
        if self.config.version != 2 {
            return Err(Error::Invalid("upgrade address book first"));
        }
        Ok(())
    }
    fn group_rows(&mut self) -> Result<Vec<Vec<String>>> {
        self.require_groups()?;
        self.sdk
            .read(|r| r.query("SELECT id,name,document FROM groups ORDER BY name,id", &[]))?
            .iter()
            .map(|r| {
                let values = strings(r)?;
                if values.len() != 3 {
                    return Err(Error::Invalid("invalid group"));
                }
                valid_key(&values[0])?;
                if group_name(&values[1])? != values[1]
                    || serde_json::from_str::<Json>(&values[2])?
                        != json!({"version":1,"name":values[1]})
                {
                    return Err(Error::Invalid("invalid group"));
                }
                Ok(values)
            })
            .collect()
    }
    fn membership_rows(&mut self) -> Result<Vec<Vec<String>>> {
        self.require_groups()?;
        self.sdk
            .read(|r| {
                r.query(
                    "SELECT id,group_id,contact_id,state FROM memberships ORDER BY id",
                    &[],
                )
            })?
            .iter()
            .map(|r| {
                let v = strings(r)?;
                if v.len() != 4 {
                    return Err(Error::Invalid("invalid membership"));
                }
                valid_key(&v[1])?;
                valid_key(&v[2])?;
                if v[0] != format!("{}:{}", v[1], v[2])
                    || !["joined", "left"].contains(&v[3].as_str())
                {
                    return Err(Error::Invalid("invalid membership"));
                }
                Ok(v)
            })
            .collect()
    }
    fn available_group(&mut self, id: &str) -> Result<String> {
        valid_key(id)?;
        if self
            .sdk
            .list_conflicts()?
            .iter()
            .any(|c| c.table == 2 && c.key == id)
        {
            return Err(Error::Conflict);
        }
        self.group_rows()?
            .into_iter()
            .find(|r| r[0] == id)
            .map(|r| r[1].clone())
            .ok_or(Error::NotFound)
    }
    fn check_group_name(&mut self, id: &str, name: &str) -> Result<()> {
        if self
            .group_rows()?
            .iter()
            .any(|r| r[0] != id && r[1].to_lowercase() == name.to_lowercase())
        {
            return Err(Error::DuplicateGroupName);
        }
        Ok(())
    }
    pub fn groups(&mut self, command: GroupCommand) -> Result<Json> {
        self.require_groups()?;
        match command {
            GroupCommand::ContactGroups { id } => {
                valid_key(&id)?;
                let mut groups = self.groups(GroupCommand::List)?;
                let members = self.membership_rows()?;
                let conflicts = self.sdk.list_conflicts()?;
                for g in groups.as_array_mut().unwrap() {
                    let member = members
                        .iter()
                        .find(|m| m[1] == g["id"].as_str().unwrap() && m[2] == id);
                    g["state"] = json!(member.map(|m| m[3].clone()));
                    g["member_conflict"] = json!(member.is_some_and(|m| {
                        conflicts.iter().any(|c| c.table == 3 && c.key == m[0])
                    }));
                }
                Ok(groups)
            }
            GroupCommand::SetContactGroups { id, changes } => {
                self.writable(&id)?;
                if changes.len() > 1000 {
                    return Err(Error::Invalid("at most 1000 memberships"));
                }
                let conflicts = self.sdk.list_conflicts()?;
                let mut seen = BTreeSet::new();
                for change in &changes {
                    self.available_group(&change.group_id)?;
                    if !seen.insert(&change.group_id) {
                        return Err(Error::Invalid("duplicate membership"));
                    }
                    if conflicts
                        .iter()
                        .any(|c| c.table == 3 && c.key == format!("{}:{}", change.group_id, id))
                    {
                        return Err(Error::Conflict);
                    }
                }
                let (changed,_)=self.sdk.write_transaction(|w|{
                    for c in &changes {
                        let rows=w.query("SELECT state FROM memberships WHERE id=?1",&[Value::Text(format!("{}:{}",c.group_id,id))])?;
                        if rows.first().and_then(|r|r.first())!=c.expected.clone().map(Value::Text).as_ref() {return Ok(false);}
                    }
                    for c in &changes {w.execute("INSERT INTO memberships VALUES (?1,?2,?3,?4) ON CONFLICT(id) DO UPDATE SET state=excluded.state",&[Value::Text(format!("{}:{}",c.group_id,id)),Value::Text(c.group_id.clone()),Value::Text(id.clone()),Value::Text(if c.joined {"joined"} else {"left"}.into())])?;}
                    Ok(true)
                })?;
                if !changed {
                    return Err(Error::EditStale);
                }
                Ok(Json::Null)
            }

            GroupCommand::List => {
                let rows = self.group_rows()?;
                let conflicts = self.sdk.list_conflicts()?;
                let members = self.membership_rows()?;
                let mut result = Vec::new();
                for r in &rows {
                    let conflict = conflicts.iter().any(|c| c.table == 2 && c.key == r[0]);
                    let mut count = 0;
                    let mut pending = 0;
                    for m in members.iter().filter(|m| m[1] == r[0]) {
                        if conflicts.iter().any(|c| c.table == 3 && c.key == m[0]) {
                            pending += 1;
                            continue;
                        }
                        if !conflict
                            && m[3] == "joined"
                            && self.get(&m[2])?.is_some_and(|c| !c.has_conflict)
                        {
                            count += 1;
                        }
                    }
                    result.push(json!({"id":r[0],"name":r[1],"count":count,"pending":pending,"has_conflict":conflict,"duplicate":rows.iter().filter(|x|x[1].to_lowercase()==r[1].to_lowercase()).count()>1}));
                }
                Ok(json!(result))
            }
            GroupCommand::Create { name } => {
                let name = group_name(&name)?;
                let id = random_id()?;
                self.check_group_name(&id, &name)?;
                self.sdk.write_transaction(|w| {
                    w.execute(
                        "INSERT INTO groups VALUES (?1,?2,?3)",
                        &group_row(&id, &name),
                    )
                })?;
                Ok(json!({"id":id,"name":name}))
            }
            GroupCommand::Rename { id, expected, name } => {
                if self.available_group(&id)? != expected {
                    return Err(Error::EditStale);
                }
                let name = group_name(&name)?;
                self.check_group_name(&id, &name)?;
                self.sdk.write_transaction(|w| {
                    w.execute(
                        "UPDATE groups SET name=?2,document=?3 WHERE id=?1",
                        &group_row(&id, &name),
                    )
                })?;
                Ok(Json::Null)
            }
            GroupCommand::Delete { id, expected } => {
                if self.available_group(&id)? != expected {
                    return Err(Error::EditStale);
                }
                self.sdk.write_transaction(|w| {
                    w.execute("DELETE FROM groups WHERE id=?1", &[Value::Text(id)])
                })?;
                Ok(Json::Null)
            }
            GroupCommand::Members { id } => {
                self.available_group(&id)?;
                let conflicts = self.sdk.list_conflicts()?;
                let result=self.membership_rows()?.into_iter().filter(|r|r[1]==id).map(|r|json!({"id":r[0],"contact_id":r[2],"state":r[3],"has_conflict":conflicts.iter().any(|c|c.table==3&&c.key==r[0])})).collect::<Vec<_>>();
                Ok(json!(result))
            }
            GroupCommand::SetMembers { id, changes } => {
                self.available_group(&id)?;
                if changes.len() > 1000 {
                    return Err(Error::Invalid("at most 1000 membership changes"));
                }
                let conflicts = self.sdk.list_conflicts()?;
                let mut seen = BTreeSet::new();
                for change in &changes {
                    valid_key(&change.contact_id)?;
                    if !seen.insert(&change.contact_id) {
                        return Err(Error::Invalid("duplicate membership change"));
                    }
                    if change.joined && self.get(&change.contact_id)?.is_none_or(|c| c.has_conflict)
                    {
                        return Err(Error::EditStale);
                    }
                    if conflicts
                        .iter()
                        .any(|c| c.table == 3 && c.key == format!("{}:{}", id, change.contact_id))
                    {
                        return Err(Error::Conflict);
                    }
                }
                let (changed,_)=self.sdk.write_transaction(|w| {
                    for c in &changes {
                        let rows=w.query("SELECT state FROM memberships WHERE id=?1",&[Value::Text(format!("{}:{}",id,c.contact_id))])?;
                        let current=rows.first().and_then(|r|r.first());
                        let expected=c.expected.clone().map(Value::Text);
                        if current!=expected.as_ref() {return Ok(false);}
                    }
                    for c in &changes {
                        w.execute("INSERT INTO memberships VALUES (?1,?2,?3,?4) ON CONFLICT(id) DO UPDATE SET state=excluded.state", &[Value::Text(format!("{}:{}",id,c.contact_id)),Value::Text(id.clone()),Value::Text(c.contact_id.clone()),Value::Text(if c.joined {"joined"} else {"left"}.into())])?;
                    }
                    Ok(true)
                })?;
                if !changed {
                    return Err(Error::EditStale);
                }
                Ok(Json::Null)
            }
            GroupCommand::Contacts {
                group,
                search,
                offset,
            } => {
                if let Some(g) = &group
                    && !g.is_empty()
                {
                    self.available_group(g)?;
                }
                let conflicts = self.sdk.list_conflicts()?;
                let available = self
                    .group_rows()?
                    .into_iter()
                    .filter(|r| !conflicts.iter().any(|c| c.table == 2 && c.key == r[0]))
                    .map(|r| r[0].clone())
                    .collect::<BTreeSet<_>>();
                let mut joined = BTreeMap::<String, BTreeSet<String>>::new();
                let mut pending = BTreeSet::new();
                for m in self.membership_rows()? {
                    if conflicts.iter().any(|c| c.table == 2 && c.key == m[1]) {
                        pending.insert(m[2].clone());
                        continue;
                    }
                    if !available.contains(&m[1]) {
                        continue;
                    }
                    if conflicts.iter().any(|c| c.table == 3 && c.key == m[0]) {
                        pending.insert(m[2].clone());
                    } else if m[3] == "joined" {
                        joined.entry(m[2].clone()).or_default().insert(m[1].clone());
                    }
                }
                let mut result = Vec::new();
                let mut skip = offset;
                for page in 0..201 {
                    let contacts = self.list(&search, 500, page * 500)?;
                    let done = contacts.len() < 500;
                    for c in contacts {
                        let matches = match &group {
                            None => true,
                            Some(g) if g.is_empty() => {
                                !joined.contains_key(&c.id) && !pending.contains(&c.id)
                            }
                            Some(g) => {
                                !c.has_conflict && joined.get(&c.id).is_some_and(|s| s.contains(g))
                            }
                        };
                        if matches {
                            if skip > 0 {
                                skip -= 1;
                            } else {
                                result.push(c);
                                if result.len() == 50 {
                                    return Ok(json!(result));
                                }
                            }
                        }
                    }
                    if done {
                        return Ok(json!(result));
                    }
                }
                Err(Error::Invalid("too many contacts"))
            }
            GroupCommand::Conflicts => {
                let mut result = Vec::new();
                for conflict in self
                    .sdk
                    .list_conflicts()?
                    .into_iter()
                    .filter(|c| c.table != 1)
                {
                    if ![2, 3].contains(&conflict.table) {
                        return Err(Error::Invalid("unknown conflict entity"));
                    }
                    let mut candidates = Vec::new();
                    for h in conflict.heads {
                        let row = h.row.as_ref().map(|r| strings(r)).transpose()?;
                        if let Some(r) = &row {
                            if (conflict.table == 2 && r.len() != 3)
                                || (conflict.table == 3 && r.len() != 4)
                                || r[0] != conflict.key
                            {
                                return Err(Error::Invalid("invalid entity candidate"));
                            }
                            if conflict.table == 2 {
                                valid_key(&r[0])?;
                                group_name(&r[1])?;
                            } else {
                                valid_key(&r[1])?;
                                valid_key(&r[2])?;
                                if r[0] != format!("{}:{}", r[1], r[2])
                                    || !["joined", "left"].contains(&r[3].as_str())
                                {
                                    return Err(Error::Invalid("invalid membership candidate"));
                                }
                            }
                        }
                        candidates.push(json!({"version":VersionId::from(h.id),"row":row}));
                    }
                    let title = if conflict.table == 2 {
                        candidates
                            .iter()
                            .filter_map(|c| c["row"][1].as_str())
                            .collect::<BTreeSet<_>>()
                            .into_iter()
                            .collect::<Vec<_>>()
                            .join(" / ")
                    } else {
                        let (_, contact) = conflict
                            .key
                            .split_once(':')
                            .ok_or(Error::Invalid("invalid membership key"))?;
                        self.get(contact)?
                            .map(|c| c.data.display_name)
                            .unwrap_or_else(|| "联系人不可用".into())
                    };
                    result.push(json!({"table":conflict.table,"entity_type":if conflict.table==2 {"group"}else{"membership"},"id":conflict.key,"title":title,"candidates":candidates}));
                }
                Ok(json!(result))
            }
            GroupCommand::Resolve {
                table,
                id,
                observed,
                value,
            } => {
                if ![2, 3].contains(&table) || observed.is_empty() || observed.len() > 1000 {
                    return Err(Error::Invalid("entity resolution bounds"));
                }
                let row = if table == 2 {
                    valid_key(&id)?;
                    value
                        .map(|v| group_name(&v).map(|name| group_row(&id, &name)))
                        .transpose()?
                } else {
                    let Some((group, contact)) = id.split_once(':') else {
                        return Err(Error::Invalid("invalid member id"));
                    };
                    valid_key(group)?;
                    valid_key(contact)?;
                    let state = value
                        .filter(|v| ["joined", "left"].contains(&v.as_str()))
                        .ok_or(Error::Invalid("member state required"))?;
                    Some(vec![
                        Value::Text(id.clone()),
                        Value::Text(group.into()),
                        Value::Text(contact.into()),
                        Value::Text(state),
                    ])
                };
                self.sdk.resolve(
                    table,
                    &id,
                    observed
                        .iter()
                        .map(VersionId::operation)
                        .collect::<Result<Vec<_>>>()?,
                    row,
                )?;
                Ok(Json::Null)
            }
        }
    }
}
