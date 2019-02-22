## Assignment
Create a Content Management System as a Sinatra application.

## Running The Code
To run the program:
  1. download the program
  * run `$ bundle install` to install all dependencies
  * run `$ ruby twenty_one.rb`
  *  navigate to `localhost:4567` using a browser

To run rubocop:
  1. use version 0.46.0 (I was able to satisfy all but three small Rubocop complaints)

## Cross-browser Compatibility
The application works as expected on Chrome and FireFox.

## Baseline Features
1. User can view text documents (.txt, .md)
* User can rename or delete existing documents
* Styled Success and Error messages are displayed to User, list of files is formatted with a specific font and padding
* User can edit content of existing text documents
* There is a sign-in option and certain functionality (rename, delete) requires a user to be signed in
* User passwords are stored in a hashed format for security
* Tests exist for all functionality, including values stored in the session

## Additional Features
1. Only Markdown, MS Word Doc, and Text (.txt) files can be created natively within the application
* User can duplicate existing documents
* User can create a new account. New account creation signs the user in automatically, immediately allowing them to manipulate files
* User can upload images (.jpg/.jpeg, .png, .gif files) or PDF files and they will display properly


## Design Decisions
1. The `edit` link is now a button, and that functionality is only available for text documents.
* The `edit`, `duplicate`, `rename`, and `delete` buttons only display when a user is signed in.
* Only .doc, .md, and .txt files can be created natively. PDFs, images (.jpg, .jpeg, .gif, .png), or .md or .txt files can be uploaded. I was unable to render uploaded .doc files properly so those are not allowed.
* Renaming only allows the user to access the name of the file. This is in order to prevent possible corruption from inadvertent changes to the extension type.
* Uploaded files must be 1.5 MB or smaller.
* The user is asked to confirm their action when deleting a file.
* File names are transformed to CamelCase on save (creation, rename, or upload) and files are displayed alphabetically.
* Passwords are hidden from display.
* New user passwords are specified in the type of characters they must contain (start with an uppercase letter, contain at least one lowercase, one number and one special character: !\*-?)
* Every page other than the index features a `cancel` button to return the user to the index.
* Buttons are styled with hover effects to make the page slightly more interactive for the user. Success and Error messages are styled with different background colors for ease of disambiguation (though I worry that the red and green I chose are not ideal for those with red-green color blindness).
