library(nycflights13)
library(tidyverse)



# 知识点1：学习累加和滚动聚合
x <- 1:10
cumsum(x)
cummean(x)
cummax(x)

flights |> group_by(year, month, day) |>
   summarise(
    mean = mean(dep_delay, na.rm = TRUE)
   ) 
