How the Script Works (Step-by-Step)
 Step 1: Ask for Order ID
•	You’ll be prompted:
Enter the Order ID:
•	It searches OpenStack servers for this string and saves the filtered list to a CSV file.

 Step 2: Identify Subscription ID
•	From the filtered servers, it shows the Subscription ID (based on 2nd column in the CSV).
•	Then prompts you:
Enter the Subscription ID from above to filter further:

Step 3: Get Server and Volume Info
•	Finds all volumes attached to servers under that subscription.
•	Saves Server ID and Volume IDs in a temporary file.

Step 4: Ask to Take Snapshots
•	Prompts:
Would you like to take snapshots of all volumes? (yes/no)
•	If you choose "yes", it continues.
________________________________________
Step 5: Filter Volumes Based on Conditions
For each volume, it will:
Skip snapshot if:
•	volume_image_metadata contains "ChainLoader"
•	Volume size is 50 GB or less
 It will also:
•	Replace client01 in the volume name with Host01
•	Create a snapshot only if status is:
o	available (normal)
o	in-use (with --force)
________________________________________
Step 6: Report Generation
•	For each processed volume, it logs:
o	Order ID
o	Subscription ID
o	Host ID
o	Volume Name (with client01 replaced)
o	Volume ID
o	Size
o	Snapshot ID
o	Status of snapshot (created/skipped/etc.)
This is saved in a final file:
snapshot_report.csv

📄 Output File Example: snapshot_report.csv
Order ID	Subscription ID	Host Number	Volume Name	Volume ID	Size (GB)	Snapshot ID	Status
ORD001	SUB1234	srv-uuid-123	Host01-root	vol-aaa111	100	snap-bbb222	created

