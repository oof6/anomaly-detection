# Questions 


#### **Access Permissions:** What element (specify file and line #) grants the SNS subscription permission to send messages to your API? Locate and explain your answer.
- lines 101-104 in the build.yaml grant the SNS subscription permission to send messages to the API, because thats where the SNS subscription gets permission to send messages over the internet to the FastAPI that is listening at the address of the Elastic IP



#### **Event flow and reliability:** Trace the path of a single CSV file from the moment it is uploaded to raw/ in S3 until the FastAPI app processes it. What happens if the EC2 instance is down or the /notify endpoint returns an error? How does SNS behave (e.g., retries, dead-letter behavior), and what would you change if this needed to be production-grade?
-  First the file is put into /raw, then the event trigger is set off by the arrival of the csv. Then S3 sends a message to the SNS Topic about the arrival. Then the SNS checks its messages, if the SNS doesnt retrieve the message by a certain amount of time it becomes a dead letter and expires. If SNS retrieves the message, then it sends a POST request to the FastAPI app. When FastAPI gets it, it parses the message and hands the tasks off to BackgroundTasks. If the messages isn't recieved, the SNS will attempt to retry sending the message a few times.

- In order to raise this to production levels, I would implement a dead letter queue. I would also utilize a buffer queue in the case that the instance goes down, so undelivered messages would remain in the queue until the instance returns instead of being lost.


#### **IAM and least privilege:** The IAM policy for the EC2 instance grants full access to one S3 bucket. List the specific S3 operations the application actually performs (e.g., GetObject, PutObject, ListBucket). Could you replace the “full access” policy with a minimal set of permissions that still allows the app to work? What would that policy look like?
- The operations the application performs are GetObject, PutObject, DeleteObject, and ListBucket. Yes you could, you could limit which parts have access to each operation. You could limit ListBucket to Bucket/* and give permissions to the bucket to GetObject and PutObject. We can also remove DeleteObject since we currently dont need it for either level for the app to work. 



#### **Architecture and scaling:** This solution uses batch-file  baseline in memory and in S3. How would the design change if you needed to handle 100x more CSV files per hour, or if multiple EC2 instances were processing files from theevents (S3 + SNS) to drive processing, with a rolling statistical same bucket? Address consistency of the shared baseline.json, concurrent processing, and any tradeoffs.
- If you share the baseline as it is among more than one EC2 instance, they would be continously overwriting the others modifications. To accomodate these changes you could implement DynamoDB so that each instance could make incrememental changes to the DB and not risk overwriting the others changes when working at the same time. But implementing this would increase AWS costs and make things more complex. 
-  If I needed to handle 100x more CSV files, I could implement a queue service so that the EC2 only recieves what it is capable of handling at a time and it doesnt get overwhelmed. Introducing this would also mean that there is another step between the SNS and the Instance which could slightly slow down the speed at which the message is seen.
