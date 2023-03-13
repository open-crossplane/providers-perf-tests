Prepare files, run in order.

1. Load all the files
vim *.* 

2. Remove unused stuff. The macro under q is already present and removes until
Experiment Duraition line 
```bash
bufdo normal@q w 
bufdo :%s/time=".*msg="\(.*\) .* \\n"/\1/g
bufdo :%s/time=".*msg="\(.*\) .*\\n"/\1/g
```

3. Format values output
`bufdo :%s/[0-9.]\+/\=system('numfmt --to=si --format %.2f', submatch(0))`

4. Transpose data to columnar layout
`bufdo :%d|:r! bash -c "datamash -t: transpose <% | column -t -s:"`

5. Delete top empty line
`bufdo :g/^$/d`
