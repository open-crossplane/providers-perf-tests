Prepare files, run in order.

1. Load all the files
vim *.txt

2. Remove unused stuff. The macro under q is already present and removes until
Experiment Duraition line 
```bash
bufdo normal@q w 
bufdo :%s/^.*msg="\(.*\) \([0-9.]\+\).*$/\1 \2/g
```

3. Format values output
`bufdo :%s/[0-9.]\+/\=system('numfmt --format %.2f', submatch(0))`

4. Transpose data to columnar layout with ; separator to make the file CSV
compatible 
`bufdo :%d|:r! bash -c "datamash -t: transpose <% | column -t -s: --output-separator=';'"`

5. Delete top empty line
`bufdo :g/^$/d`

6. Add file name to first column
`bufdo :%s/\v^/\=expand("%:t:r") .expand("; ")/g`

7. Combine results
<!-- `fd --extension=txt | sort -V | xargs tail -n +1 | sed 's#> ./#> #g'` -->
`fd --extension=txt | sort -V | xargs cat`

8. Format columns
`%s/ of Registry/ seconds /g | %s/CPU/CPU %/g`
