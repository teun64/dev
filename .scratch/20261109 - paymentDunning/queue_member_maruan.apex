// Adds Maruan Mourad as a user member of queue gqCasePayment5 (DE), next to the guAftersalesDE group from the queue metadata.
// Usernames differ per org, so this is a data step. Run AFTER the queue deploy (a queue metadata deploy replaces its members).
// Run: sf apex run -o <org> -f ".scratch/20261109 - paymentDunning/queue_member_maruan.apex" | grep CHECK
Group q = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'gqCasePayment5'];
List<User> u = [SELECT Id, Name, IsActive FROM User WHERE Username LIKE 'mmourad@movingintelligence.de%' LIMIT 1];
if (u.isEmpty()) { System.debug('CHECK Maruan not found'); return; }
if ([SELECT COUNT() FROM GroupMember WHERE GroupId = :q.Id AND UserOrGroupId = :u[0].Id] > 0) { System.debug('CHECK already member'); return; }
insert new GroupMember(GroupId = q.Id, UserOrGroupId = u[0].Id);
System.debug('CHECK added ' + u[0].Name + ' (active=' + u[0].IsActive + ') to gqCasePayment5');
