# Last-word conversion only during a typing session

The target is not “whatever token sits left of the caret.” A non-empty selection is always the target. With no selection, last-word conversion runs only while a **typing session** is live (character keys, backspace, trailing space). Click, caret-moving keys, focus change, and paste end the session; after that the user must select.

Eligibility comes from the session; the characters still come from the field. The obvious alternative — always bound a token from the Accessibility caret — would convert after a click or a field switch, which is not the product.
